package com.blindcane.guardian.framework.config;

import com.baomidou.mybatisplus.core.handlers.MetaObjectHandler;
import org.apache.ibatis.reflection.MetaObject;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

/**
 * created_at / updated_at 自动填充。
 *
 * <p>放在这里而不是依赖数据库的 ON UPDATE CURRENT_TIMESTAMP：
 * 数据库默认值在「显式传入 NULL」时不会生效，且时区跟随 MySQL 会话，
 * 由应用统一填充可以保证时间口径与业务时区一致。
 */
@Component
public class MetaObjectAutoFillHandler implements MetaObjectHandler {

    @Override
    public void insertFill(MetaObject metaObject) {
        LocalDateTime now = LocalDateTime.now();
        strictInsertFill(metaObject, "createdAt", LocalDateTime.class, now);
        strictInsertFill(metaObject, "updatedAt", LocalDateTime.class, now);
    }

    @Override
    public void updateFill(MetaObject metaObject) {
        strictUpdateFill(metaObject, "updatedAt", LocalDateTime.class, LocalDateTime.now());
    }
}
