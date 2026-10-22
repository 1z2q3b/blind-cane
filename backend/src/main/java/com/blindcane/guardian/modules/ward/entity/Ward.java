package com.blindcane.guardian.modules.ward.entity;

import com.baomidou.mybatisplus.annotation.FieldFill;
import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/** 被监护人档案（ward）。 */
@Data
@TableName("ward")
public class Ward {

    @TableId(type = IdType.AUTO)
    private Long id;

    private String name;

    /** 与操作家属的关系：父亲/母亲/配偶/其他。 */
    private String relation;

    private Integer birthYear;

    private String homeAddress;

    /** 家庭住址经度（家属手动定位后写入，可空）。 */
    private Double homeLng;

    /** 家庭住址纬度（家属手动定位后写入，可空）。 */
    private Double homeLat;

    /** 被监护人随身电话，一键拨号用。空串表示未填写（不是 null，见 V4 迁移说明）。 */
    private String contactPhone;

    /** 病史备注，落库前由 AesCryptoUtil 加密成 Base64 密文。 */
    private String medicalNotes;

    /** 主监护人 family_user.id。 */
    private Long primaryUserId;

    @TableField(fill = FieldFill.INSERT)
    private LocalDateTime createdAt;

    @TableField(fill = FieldFill.INSERT_UPDATE)
    private LocalDateTime updatedAt;
}
