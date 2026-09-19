package com.blindcane.guardian.modules.user.entity;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 家属用户（family_user）。App 的操作者，即被监护人的子女/配偶等。 */
@Data
@TableName("family_user")
public class FamilyUser {

    public static final int STATUS_NORMAL = 0;
    public static final int STATUS_DISABLED = 1;

    @TableId(type = IdType.AUTO)
    private Long id;

    /** 手机号，登录账号，唯一。 */
    private String phone;

    private String nickname;

    private String avatar;

    /** 0 正常 / 1 禁用。 */
    private Integer status;

    /** 通知偏好 JSON，例如 {"SOS":{"push":true,"inApp":true}}。 */
    private String notificationSettings;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;
}
