package com.blindcane.guardian.modules.auth.dto;

/**
 * 用户信息（登录响应内嵌）。
 *
 * <p>不回传 medicalNotes 等敏感字段；这里是家属自己的账号信息，只含非敏感项。
 */
public record UserInfoVO(Long id, String phone, String nickname, String avatar) {
}
