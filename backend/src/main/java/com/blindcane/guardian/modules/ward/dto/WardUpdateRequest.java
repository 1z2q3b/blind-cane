package com.blindcane.guardian.modules.ward.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.Size;

/**
 * 更新被监护人档案。字段均可选，为 null 表示「不修改」。
 *
 * <p>用 null 而不是空字符串判断「不修改」：住址被清空也是有意义的语义，
 * 但病史备注若传空字符串则按「清空」处理，二者不冲突。
 */
public record WardUpdateRequest(

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
