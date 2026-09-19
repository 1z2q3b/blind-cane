package com.blindcane.guardian.modules.location.service;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.blindcane.guardian.framework.redis.RedisGuard;
import com.blindcane.guardian.modules.location.dto.LatestLocation;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;

/**
 * 最新位置缓存（Redis）。
 *
 * <p>位置上报是 10 秒一次的高频写，而家属端打开地图时会立刻查一次当前位置。
 * 若直接读 MySQL，既有写放大也要走空间索引排序；放 Redis 后实时读是 O(1)，
 * MySQL 只承担「历史轨迹」（二期）的职责。这就是提示词里「位置双写」的由来。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class LocationCacheService {

    private static final String KEY_PREFIX = "loc:ward:";

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final BlindcaneProperties properties;
    private final RedisGuard redisGuard;

    public void save(Long wardId, LatestLocation location) {
        String json;
        try {
            json = objectMapper.writeValueAsString(location);
        } catch (JsonProcessingException e) {
            log.warn("位置缓存序列化失败 wardId={}", wardId, e);
            return;
        }
        // 缓存写失败不能影响位置上报主链路，MySQL 才是最终数据源
        redisGuard.run(() -> redisTemplate.opsForValue().set(KEY_PREFIX + wardId, json,
                Duration.ofMinutes(properties.getLocation().getRedisTtlMinutes())));
    }

    /** 读最新位置；Redis 不可用、无缓存或缓存损坏都返回 null，由调用方决定降级展示。 */
    public LatestLocation get(Long wardId) {
        String json = redisGuard.call(() -> redisTemplate.opsForValue().get(KEY_PREFIX + wardId),
                () -> null);
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readValue(json, LatestLocation.class);
        } catch (Exception e) {
            log.warn("位置缓存解析失败 wardId={}, 原始值={}", wardId, json);
            return null;
        }
    }

    public void evict(Long wardId) {
        redisGuard.run(() -> redisTemplate.delete(KEY_PREFIX + wardId));
    }
}
