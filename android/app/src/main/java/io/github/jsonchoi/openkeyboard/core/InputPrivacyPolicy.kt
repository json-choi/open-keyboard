package io.github.jsonchoi.openkeyboard.core

/**
 * Fields the keyboard must not read: passwords, PINs, unknown input classes and hosts that ask for
 * no personalized learning. The keyboard still types there, but shortcuts and cursor reads stay off.
 */
object InputPrivacyPolicy {
    private val fieldHint = Regex("""(?:password|passcode|\bPIN\b|\bOTP\b|one[- ]time|verification[ _-]?code|credit[ _-]?card|card[ _-]?number|account[ _-]?number|passport|비밀번호|패스워드|암호|인증[ ]?번호|보안[ ]?코드|카드[ ]?번호|계좌[ ]?번호|여권[ ]?번호|パスワード|暗証番号|認証コード|カード番号|口座番号|旅券番号|密码|密碼|验证码|驗證碼|認證碼|银行卡|信用卡|账号|帳號|护照|護照)""", RegexOption.IGNORE_CASE)
    fun blocksEditor(inputType: Int?, imeOptions: Int = 0, hint: String? = null): Boolean {
        // Only plain text (class 1) is readable; IME_FLAG_NO_PERSONALIZED_LEARNING (0x01000000) also blocks.
        if (inputType == null || inputType and 0x0f != 1 || imeOptions and 0x01000000 != 0) return true
        // URI, email, postal address, password, visible password, web email and web password variations.
        return inputType and 0x0ff0 in setOf(16, 32, 112, 128, 144, 208, 224) || fieldHint.containsMatchIn(hint.orEmpty())
    }
}
