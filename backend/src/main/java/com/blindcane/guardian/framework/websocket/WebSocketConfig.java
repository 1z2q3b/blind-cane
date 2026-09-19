package com.blindcane.guardian.framework.websocket;

import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.scheduling.TaskScheduler;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketTransportRegistration;

/**
 * WebSocket / STOMP 配置。
 *
 * <p>关键决策：
 * <ul>
 *   <li>用 SimpleBroker（内存）而不是 RabbitMQ/ActiveMQ 外部代理：MVP 单实例部署，
 *       引入外部 broker 只会增加一套中间件运维成本。多实例部署时再换成
 *       {@code enableStompBrokerRelay} 即可，业务代码不变。</li>
 *   <li>心跳 30 秒（提示词 7.3），需要显式提供 TaskScheduler，
 *       否则 SimpleBroker 会忽略心跳配置 —— 这是最容易被漏掉的一点。</li>
 *   <li>握手路径 /ws 在 SecurityConfig 里放行：WebSocket 握手无法携带自定义请求头，
 *       真正的认证放在 STOMP 的 CONNECT 帧里做。</li>
 * </ul>
 */
@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final StompAuthChannelInterceptor stompAuthChannelInterceptor;

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        registry.enableSimpleBroker("/topic")
                .setHeartbeatValue(new long[]{30_000L, 30_000L})
                .setTaskScheduler(webSocketHeartbeatScheduler());
        registry.setApplicationDestinationPrefixes("/app");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // setAllowedOriginPatterns 必须开着：家属端用 flutter run -d chrome 调试时
        // 握手请求的 Origin 是随机端口的 localhost，不放行会直接被拒绝
        registry.addEndpoint("/ws").setAllowedOriginPatterns("*");
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(stompAuthChannelInterceptor);
    }

    @Override
    public void configureWebSocketTransport(WebSocketTransportRegistration registration) {
        // 位置推送是高频小包，限制缓冲区防止慢客户端拖垮服务端内存
        registration.setMessageSizeLimit(128 * 1024)
                .setSendBufferSizeLimit(512 * 1024)
                .setSendTimeLimit(20_000);
    }

    /**
     * 心跳调度器。
     *
     * <p>显式声明的原因：SimpleBroker 只有在拿到 TaskScheduler 时才会真正按
     * heartbeat 配置发送心跳，否则该配置被静默忽略，客户端会误判连接已死。
     */
    @Bean
    public TaskScheduler webSocketHeartbeatScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setThreadNamePrefix("ws-heartbeat-");
        scheduler.setPoolSize(2);
        scheduler.setDaemon(true);
        scheduler.initialize();
        return scheduler;
    }
}
