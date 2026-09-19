package com.blindcane.guardian.framework.security;

import com.blindcane.guardian.common.result.ApiResponse;
import com.blindcane.guardian.common.result.ErrorCode;
import com.blindcane.guardian.framework.config.BlindcaneProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

/**
 * Spring Security 配置：纯 JWT 无状态鉴权。
 *
 * <p>关键决策：
 * <ul>
 *   <li>Mock 接口是否放行取决于 {@code blindcane.simulator.enabled}。生产 profile
 *       关掉模拟器后，{@code /api/v1/mock/**} 自动回到「需登录」状态，不会裸奔。</li>
 *   <li>STOMP 握手路径 {@code /ws/**} 放行，因为 WebSocket 握手无法携带自定义头，
 *       真正的订阅鉴权放在 STOMP 的 CONNECT/SUBSCRIBE 拦截器里做。</li>
 *   <li>认证/授权失败的出口统一在这里，返回 401/403 + 统一响应体，
 *       前端拦截器只需判断 HTTP 状态码即可决定「刷新令牌」还是「提示无权限」。</li>
 * </ul>
 */
@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthenticationFilter;
    private final BlindcaneProperties properties;
    private final ObjectMapper objectMapper;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        String[] permitAllPaths = properties.getSecurity().getPermitAllPaths().toArray(new String[0]);
        boolean simulatorEnabled = properties.getSimulator().isEnabled();

        http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(Customizer.withDefaults())
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(registry -> {
                    if (permitAllPaths.length > 0) {
                        registry.requestMatchers(permitAllPaths).permitAll();
                    }
                    registry.requestMatchers("/ws/**").permitAll();
                    if (simulatorEnabled) {
                        registry.requestMatchers("/api/v1/mock/**").permitAll();
                    }
                    registry.anyRequest().authenticated();
                })
                .exceptionHandling(handling -> handling
                        .authenticationEntryPoint((request, response, ex) ->
                                writeJson(response, HttpServletResponse.SC_UNAUTHORIZED, ErrorCode.TOKEN_INVALID))
                        .accessDeniedHandler((request, response, ex) ->
                                writeJson(response, HttpServletResponse.SC_FORBIDDEN, ErrorCode.NO_GUARDIAN_PERMISSION)))
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    private void writeJson(HttpServletResponse response, int httpStatus, ErrorCode errorCode) throws IOException {
        response.setStatus(httpStatus);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.getWriter().write(objectMapper.writeValueAsString(ApiResponse.failure(errorCode)));
    }
}
