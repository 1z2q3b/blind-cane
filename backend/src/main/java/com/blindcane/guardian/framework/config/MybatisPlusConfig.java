package com.blindcane.guardian.framework.config;

import com.baomidou.mybatisplus.annotation.DbType;
import com.baomidou.mybatisplus.extension.plugins.MybatisPlusInterceptor;
import com.baomidou.mybatisplus.extension.plugins.inner.PaginationInnerInterceptor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * MyBatis-Plus 配置。
 *
 * <p>注意：3.5.9 起分页插件被拆分到 mybatis-plus-jsqlparser 模块，
 * 若 pom 里漏掉该依赖，这里会直接 ClassNotFoundException。
 */
@Configuration
public class MybatisPlusConfig {

    @Bean
    public MybatisPlusInterceptor mybatisPlusInterceptor() {
        MybatisPlusInterceptor interceptor = new MybatisPlusInterceptor();
        PaginationInnerInterceptor pagination = new PaginationInnerInterceptor(DbType.MYSQL);
        // 单页上限兜底：防止前端传 size=999999 把整张表拉下来
        pagination.setMaxLimit(200L);
        // 页码超出总页数时返回空列表而不是第一页，避免前端分页器来回跳
        pagination.setOverflow(false);
        interceptor.addInnerInterceptor(pagination);
        return interceptor;
    }
}
