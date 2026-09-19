package com.blindcane.guardian.modules.ward.entity;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 监护关系（ward_guardian）。一位被监护人可被多位家属共同监护。
 *
 * <p>这张表是所有权限判断的唯一依据：接口拿到 wardId 后必须先查这里，
 * 不能因为「App 上没显示这个人」就默认无权限之外的情况都放行。
 */
@Data
@TableName("ward_guardian")
public class WardGuardian {

    /** 主监护人：可邀请/移除副监护人。 */
    public static final int ROLE_PRIMARY = 1;
    /** 副监护人：仅可查看与处理告警。 */
    public static final int ROLE_SECONDARY = 2;

    /** 待接受（二期邀请流程用）。 */
    public static final int INVITE_PENDING = 0;
    /** 已接受。 */
    public static final int INVITE_ACCEPTED = 1;
    /** 已解除。 */
    public static final int INVITE_REMOVED = 2;

    @TableId(type = IdType.AUTO)
    private Long id;

    private Long wardId;

    private Long userId;

    /** 1 主监护人 / 2 副监护人。 */
    private Integer role;

    /** 0 待接受 / 1 已接受 / 2 已解除。 */
    private Integer inviteStatus;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;
}
