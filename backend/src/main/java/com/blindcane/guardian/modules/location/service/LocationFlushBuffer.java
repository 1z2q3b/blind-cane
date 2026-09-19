package com.blindcane.guardian.modules.location.service;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.modules.location.entity.LocationRecord;
import com.blindcane.guardian.modules.location.mapper.LocationRecordMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 位置落库缓冲（位置双写的「MySQL 侧」）。
 *
 * <p>策略：内存队列攒批，满足任一条件即落库 ——
 * 「满 N 条」（吞吐优先）或「每 5 秒」（延迟兜底）。
 * 只满足前者会让低峰期数据长时间不落库；只满足后者在高峰会退化成逐条写。
 *
 * <p>失败处理：插入失败时把本批放回队首重试。队列设有容量上限，
 * 超限丢弃并告警，避免数据库长时间不可用时把 JVM 内存吃爆。
 * 注意位置数据的定位是「实时看 Redis，历史看 MySQL」，
 * 因此丢历史点不影响核心告警能力 —— 这也是它能容忍最终一致的原因。
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class LocationFlushBuffer {

    /** 队列容量上限，超过后丢弃最旧数据。 */
    private static final int MAX_BUFFER_SIZE = 20_000;
    /** 单次落库最大条数，避免一条 SQL 过长。 */
    private static final int MAX_BATCH_SIZE = 500;
    /** 单条记录最大重试次数，超过即丢弃。 */
    private static final int MAX_RETRY_TIMES = 3;

    private final Queue<LocationRecord> buffer = new ConcurrentLinkedQueue<>();
    private final LocationRecordMapper locationRecordMapper;
    private final BlindcaneProperties properties;

    private final AtomicLong droppedCount = new AtomicLong();
    private final AtomicLong lostCount = new AtomicLong();

    /** 收下一条待落库记录。 */
    public void add(LocationRecord record) {
        if (buffer.size() >= MAX_BUFFER_SIZE) {
            buffer.poll();
            long dropped = droppedCount.incrementAndGet();
            if (dropped % 100 == 1) {
                log.error("位置落库缓冲已满，丢弃最旧数据。累计丢弃={}", dropped);
            }
        }
        buffer.add(record);
        if (buffer.size() >= properties.getLocation().getFlushBatchSize()) {
            flush();
        }
    }

    /** 定时落库（默认 5 秒一次），保证低峰期数据也能及时写下去。 */
    @Scheduled(fixedDelayString = "${blindcane.location.flush-interval-ms:5000}")
    public void flush() {
        List<LocationRecord> batch = drain();
        if (batch.isEmpty()) {
            return;
        }
        try {
            locationRecordMapper.batchInsert(batch);
            log.debug("位置批量落库成功: {} 条", batch.size());
        } catch (Exception e) {
            // 注意打完整堆栈：MyBatis 的异常把真实原因放在 multiline 的 "### Cause:" 段里，
            // 只打 e.getMessage() 会丢掉 SQL 状态码与具体报错，排查时等于没打
            log.error("位置批量落库失败，本批 {} 条进入重试: {}", batch.size(), e.getMessage(), e);
            requeue(batch);
        }
    }

    /**
     * 失败重试：给每条记录记一次重试，超过上限就丢弃并计数。
     *
     * <p>上限的意义：像 WKT 坐标轴序写错这种「必然失败」的问题，
     * 无上限重试会每 5 秒刷一条错误日志且永远不成功，把有效日志淹没。
     */
    private void requeue(List<LocationRecord> batch) {
        List<LocationRecord> retryable = new ArrayList<>();
        for (LocationRecord record : batch) {
            if (record.getRetryCount() < MAX_RETRY_TIMES) {
                record.setRetryCount(record.getRetryCount() + 1);
                retryable.add(record);
            } else {
                long lost = lostCount.incrementAndGet();
                if (lost % 50 == 1) {
                    log.error("位置记录重试 {} 次仍失败，已丢弃。累计丢弃={}", MAX_RETRY_TIMES, lost);
                }
            }
        }
        if (retryable.isEmpty()) {
            return;
        }
        if (buffer.size() + retryable.size() <= MAX_BUFFER_SIZE) {
            buffer.addAll(retryable);
        } else {
            log.error("缓存已满，放弃重试 {} 条位置记录", retryable.size());
        }
    }

    private List<LocationRecord> drain() {
        List<LocationRecord> batch = new ArrayList<>();
        LocationRecord record;
        while (batch.size() < MAX_BATCH_SIZE && (record = buffer.poll()) != null) {
            batch.add(record);
        }
        return batch;
    }

    /** 当前积压条数，供排查与健康检查使用。 */
    public int pendingCount() {
        return buffer.size();
    }
}
