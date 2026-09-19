package com.blindcane.guardian.common.result;

import lombok.Getter;

import java.util.List;
import java.util.function.Function;

/**
 * 统一分页结构（提示词 7.1）：
 * <pre>{ "records": [...], "total": 100, "page": 1, "size": 20 }</pre>
 *
 * <p>刻意不直接返回 MyBatis-Plus 的 {@code IPage}：IPage 会把 pages/orders/
 * optimizeCountSql 等一堆内部字段序列化给前端，且耦合 ORM 实现。
 */
@Getter
public class PageResult<T> {

    private final List<T> records;
    private final long total;
    private final long page;
    private final long size;

    public PageResult(List<T> records, long total, long page, long size) {
        this.records = records;
        this.total = total;
        this.page = page;
        this.size = size;
    }

    public static <T> PageResult<T> of(List<T> records, long total, long page, long size) {
        return new PageResult<>(records, total, page, size);
    }

    /** 把 ORM 实体分页结果转换成 VO 分页结果。 */
    public static <E, V> PageResult<V> of(List<E> records, long total, long page, long size,
                                         Function<E, V> mapper) {
        return new PageResult<>(records.stream().map(mapper).toList(), total, page, size);
    }

    public static <T> PageResult<T> empty(long page, long size) {
        return new PageResult<>(List.of(), 0L, page, size);
    }
}
