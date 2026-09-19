package com.blindcane.guardian.framework.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.List;

/**
 * CORS 配置。
 *
 * <p>必须开着的原因：家属端 Flutter App 用 {@code flutter run -d chrome} 调试时，
 * 浏览器会以 localhost 的随机端口发起跨域请求。不开 CORS 时后端还没登录就被
 * 浏览器拦掉，前端只能看到 "XMLHttpRequest error"，排查成本很高。
 *
 * <p>开放范围仅限本地调试来源；生产环境应由网关按域名收敛。
 */
@Configuration
public class CorsConfig {

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        // 允许本地任意端口（Flutter web 调试端口是随机的）+ 局域网设备调试
        configuration.setAllowedOriginPatterns(List.of(
                "http://localhost:[*]",
                "http://127.0.0.1:[*]",
                "http://192.168.*.*:[*]"
        ));
        configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"));
        configuration.setAllowedHeaders(List.of("*"));
        configuration.setAllowCredentials(true);
        configuration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }
}
