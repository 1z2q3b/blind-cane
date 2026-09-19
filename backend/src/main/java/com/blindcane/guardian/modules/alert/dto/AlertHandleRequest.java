package com.blindcane.guardian.modules.alert.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** 告警处理请求。 */
public record AlertHandleRequest(

        @NotBlank(message = "处理结果不能为空")
        @Pattern(regexp = "RESOLVED|FALSE_ALARM", message = "处理结果只能是 RESOLVED 或 FALSE_ALARM")
        String result,

        @Size(max = 255, message = "备注长度不能超过 255")
        String note
) {
}
