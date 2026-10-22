package com.blindcane.guardian.modules.ward.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * 创建被监护人档案。
 *
 * @param homeLng       家庭住址经度，家属用「手动定位」确认后传入；可空
 * @param homeLat       家庭住址纬度；可空
 * @param contactPhone  被监护人随身电话，一键拨号用；可空
 * @param medicalNotes  病史备注，明文传入，落库前由服务层 AES-GCM 加密
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

        @DecimalMin(value = "-180", message = "经度超出合法范围")
        @DecimalMax(value = "180", message = "经度超出合法范围")
        Double homeLng,

        @DecimalMin(value = "-90", message = "纬度超出合法范围")
        @DecimalMax(value = "90", message = "纬度超出合法范围")
        Double homeLat,

        // 不强制 11 位手机号：老人可能只有座机，硬卡格式会让家属填不完表单。
        // 但要挡住明显是垃圾输入的超长串。
        @Pattern(regexp = "^[0-9+\\-() ]{0,20}$", message = "联系电话只能包含数字、+、-、括号和空格")
        String contactPhone,

        @Size(max = 500, message = "病史备注长度不能超过 500")
        String medicalNotes
) {
}
