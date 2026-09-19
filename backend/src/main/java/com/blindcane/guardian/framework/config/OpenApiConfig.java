package com.blindcane.guardian.framework.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Swagger / OpenAPI 文档配置。
 *
 * <p>全局挂上 bearerAuth 后，Swagger UI 右上角会出现 Authorize 按钮，
 * 填入登录返回的 accessToken 即可直接调试受保护接口，省掉手工拼 curl。
 */
@Configuration
public class OpenApiConfig {

    private static final String SECURITY_SCHEME_NAME = "bearerAuth";

    @Bean
    public OpenAPI blindcaneOpenAPI() {
        return new OpenAPI()
                .info(new Info()
                        .title("智能导盲杖 · 家属监护端 API")
                        .version("v1")
                        .description("""
                                家属监护端后端接口。
                                统一响应结构：code=0 成功，非 0 为六位错误码（101xxx 认证 / 103xxx 监护 / 104xxx 设备 / 106xxx 告警 / 109xxx 系统）。
                                演示用 Mock 接口位于 /api/v1/mock/**，仅在 blindcane.simulator.enabled=true 时可用。
                                短信为 Mock 时验证码固定 123456。"""))
                .components(new Components()
                        .addSecuritySchemes(SECURITY_SCHEME_NAME, new SecurityScheme()
                                .name(SECURITY_SCHEME_NAME)
                                .type(SecurityScheme.Type.HTTP)
                                .scheme("bearer")
                                .bearerFormat("JWT")))
                .addSecurityItem(new SecurityRequirement().addList(SECURITY_SCHEME_NAME));
    }
}
