package com.blindcane.guardian.common.util;

import com.blindcane.guardian.framework.config.BlindcaneProperties;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * 敏感字段加密（AES-256-GCM）。
 *
 * <p>为什么用 GCM 而不是 AES/CBC：GCM 自带完整性校验（认证标签），
 * 密文被篡改会直接解密失败，而 CBC 被篡改只会得到一段乱码却无法察觉。
 * 病史这类数据被静默篡改的后果比解密失败更麻烦。
 *
 * <p>存储格式：Base64( IV(12字节) || 密文 || 认证标签(16字节) )。
 * IV 每次加密随机生成并随密文一起存，因此同一明文两次加密的密文不同，
 * 攻击者无法通过比对密文判断两条记录是否相同。
 *
 * <p>密钥由配置字符串 SHA-256 派生为固定 32 字节，所以配置里填多长都不会出错。
 */
@Slf4j
@Component
public class AesCryptoUtil {

    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int IV_LENGTH = 12;
    private static final int TAG_LENGTH_BIT = 128;

    private static final SecureRandom RANDOM = new SecureRandom();

    private final SecretKey secretKey;

    public AesCryptoUtil(BlindcaneProperties properties) {
        this.secretKey = new SecretKeySpec(sha256(properties.getCrypto().getAesSecret()), "AES");
    }

    /** 加密。入参为空时原样返回，避免把 null 变成一段密文。 */
    public String encrypt(String plainText) {
        if (plainText == null || plainText.isEmpty()) {
            return plainText;
        }
        try {
            byte[] iv = new byte[IV_LENGTH];
            RANDOM.nextBytes(iv);
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, secretKey, new GCMParameterSpec(TAG_LENGTH_BIT, iv));
            byte[] cipherText = cipher.doFinal(plainText.getBytes(StandardCharsets.UTF_8));

            byte[] combined = new byte[iv.length + cipherText.length];
            System.arraycopy(iv, 0, combined, 0, iv.length);
            System.arraycopy(cipherText, 0, combined, iv.length, cipherText.length);
            return Base64.getEncoder().encodeToString(combined);
        } catch (Exception e) {
            throw new IllegalStateException("敏感字段加密失败", e);
        }
    }

    /**
     * 解密。密文损坏或被篡改时返回原值而不是抛异常：
     * 单条脏数据不应该让整个档案列表接口 500。
     */
    public String decrypt(String cipherText) {
        if (cipherText == null || cipherText.isEmpty()) {
            return cipherText;
        }
        try {
            byte[] combined = Base64.getDecoder().decode(cipherText);
            if (combined.length <= IV_LENGTH) {
                return cipherText;
            }
            Cipher cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, secretKey,
                    new GCMParameterSpec(TAG_LENGTH_BIT, combined, 0, IV_LENGTH));
            byte[] plain = cipher.doFinal(combined, IV_LENGTH, combined.length - IV_LENGTH);
            return new String(plain, StandardCharsets.UTF_8);
        } catch (Exception e) {
            log.warn("敏感字段解密失败，按原文返回。可能是密钥变更或历史明文数据：{}", e.getMessage());
            return cipherText;
        }
    }

    private static byte[] sha256(String raw) {
        try {
            return MessageDigest.getInstance("SHA-256")
                    .digest((raw == null ? "blindcane-default" : raw).getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("当前 JDK 不支持 SHA-256", e);
        }
    }
}
