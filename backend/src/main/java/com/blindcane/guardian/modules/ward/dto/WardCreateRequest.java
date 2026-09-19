package com.blindcane.guardian.modules.ward.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 创建被监护人档案。
 *
 * @param medicalNotes 病史备注，明文传入，落库前由服务层 AES-GCM 加密
 */
public record WardCreateRequest(

        @NotBlank(message = "姓名不能为空")
        @Size(max = 50, message = "姓名长度不能超过 50")
        String name,

        @Size(max = 20, message = "关系长度不能超过 20")
        String relation,

        @Min(value = 1900, message = "出生年份不合法")
        @Max(value = 2100, message = "出生年份不合法")
        Integer birthYear,

        @Size(max = 255, message = "住址长度不能超过 255")
        String homeAddress,

        @Size(max = 500, message = "病史备注长度不能超过 500")
        String medicalNotes
) {
}
