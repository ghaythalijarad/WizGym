# 📱 دليل تكامل OTP IQ - OTP IQ Integration Guide

## 🌟 نظرة عامة - Overview

تطبيق WizGym يدعم الآن خدمة OTP IQ الحقيقية لإرسال رموز التحقق عبر:
- ✅ WhatsApp
- ✅ SMS
- ✅ كلاهما معاً (Fallback)

---

## 🔧 التكوين الحالي - Current Configuration

### الوضع الحالي: **Mock Mode** 🧪

حالياً، التطبيق يعمل في وضع **Mock** (التجريبي) لأنه لا يوجد API Key مُعرّف.

في هذا الوضع:
- ✅ يتم توليد رمز OTP عشوائي
- ✅ يتم عرض الرمز في الاستجابة (mockCode)
- ✅ لا يتم إرسال رسائل حقيقية
- ⚠️ **مثالي للتطوير فقط**

---

## 🚀 تفعيل OTP IQ الحقيقي

### الخطوة 1: الحصول على API Key

1. سجّل دخول إلى [OTP IQ Dashboard](https://otpiq.com)
2. احصل على API Key الخاص بك
3. احفظ API Key في مكان آمن

### الخطوة 2: تخزين API Key في AWS Parameter Store

قم بتشغيل الأمر التالي (استبدل `YOUR_OTPIQ_API_KEY` بالمفتاح الحقيقي):

```bash
aws ssm put-parameter \
  --name "/wizgym/prod/OTPIQ_API_KEY" \
  --value "YOUR_OTPIQ_API_KEY" \
  --type "SecureString" \
  --profile wizgym-prod \
  --region us-east-1 \
  --overwrite
```

### الخطوة 3: تعطيل Mock Mode

حدّث ملف `infra/sam/template.yaml`:

```yaml
Globals:
  Function:
    Environment:
      Variables:
        # ... باقي المتغيرات
        OTPIQ_MOCK_MODE: 'false'  # غيّر من true إلى false
```

### الخطوة 4: إعادة النشر

```bash
cd infra/sam
sam build
sam deploy --config-env prod
```

### الخطوة 5: التحقق

اختبر الـ API:

```bash
curl -X POST https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/auth/phone/send-otp \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+9647831367435"}'
```

**في Mock Mode** سترى:
```json
{
  "sessionId": "abc123...",
  "mockCode": "369757",
  "message": "تم إرسال رمز التحقق"
}
```

**في Production Mode** سترى:
```json
{
  "sessionId": "abc123...",
  "message": "تم إرسال رمز التحقق"
}
```
**ملاحظة:** لن يظهر `mockCode` في الـ Production!

---

## ⚙️ تكوين إضافي - Advanced Configuration

### تغيير طريقة الإرسال (WhatsApp, SMS, Both)

في `template.yaml`:

```yaml
OTPIQ_PROVIDER: 'whatsapp-sms'  # Options: whatsapp, sms, whatsapp-sms
```

### تخصيص رسالة OTP

في `apps/api/src/routes/auth.ts`:

```typescript
const otpResponse = await otpiqService.sendOTP(
  phoneNumber,
  `مرحباً بك في WizGym! رمز التحقق: {code}` // خصص الرسالة هنا
);
```

### تغيير Sender ID (اختياري)

```yaml
OTPIQ_SENDER_ID: 'WizGym'  # اسم المرسل الذي يظهر للمستخدم
```

---

## 🔍 استكشاف الأخطاء - Troubleshooting

### المشكلة: لا يصل OTP للمستخدم

**الحل:**
1. تحقق من صحة API Key:
```bash
aws ssm get-parameter \
  --name "/wizgym/prod/OTPIQ_API_KEY" \
  --with-decryption \
  --profile wizgym-prod \
  --region us-east-1
```

2. تحقق من CloudWatch Logs:
```bash
aws logs tail /aws/lambda/sam-app-WizGymApiFunction-yE1SQSAsdJGg \
  --since 5m \
  --profile wizgym-prod \
  --region us-east-1 \
  --follow
```

3. تأكد من أن OTPIQ_MOCK_MODE = false

### المشكلة: خطأ في OTPIQ API

ابحث في اللوجز عن:
```
[OTPIQ] Failed to send OTP
[OTPIQ] Error sending OTP
```

**الأسباب المحتملة:**
- API Key غير صحيح
- رصيد OTP IQ منتهي
- رقم الهاتف بصيغة غير صحيحة
- OTPIQ service down

---

## 📊 مراقبة الاستخدام - Monitoring

### عرض سجلات OTP

```bash
# عرض آخر 100 طلب OTP
aws logs filter-log-events \
  --log-group-name /aws/lambda/sam-app-WizGymApiFunction-yE1SQSAsdJGg \
  --filter-pattern "[OTPIQ]" \
  --profile wizgym-prod \
  --region us-east-1 \
  --max-items 100
```

### رسائل اللوج المتوقعة

**في Mock Mode:**
```
[OTPIQ MOCK MODE] OTP for +9647831367435: 123456
```

**في Production Mode:**
```
[OTPIQ] API key loaded from Parameter Store
[OTPIQ] OTP sent to +9647831367435 via whatsapp-sms
```

---

## 🔒 أمان - Security

### ✅ Best Practices

1. **لا تضع API Key في الكود أبداً**
   - استخدم AWS Parameter Store فقط
   
2. **تدوير API Key بشكل دوري**
   ```bash
   aws ssm put-parameter \
     --name "/wizgym/prod/OTPIQ_API_KEY" \
     --value "NEW_API_KEY" \
     --type "SecureString" \
     --overwrite
   ```

3. **استخدم Mock Mode في Development فقط**

4. **راقب الاستخدام المشبوه**
   - عدد كبير من طلبات OTP من نفس الرقم
   - طلبات من أرقام غير عراقية (إذا كان التطبيق محلي)

---

## 📝 ملخص الحالة الحالية - Current Status Summary

| المكون | الحالة | الملاحظات |
|--------|--------|-----------|
| OTP IQ Service | ✅ مدمج | جاهز للاستخدام |
| Mock Mode | 🟡 مفعّل | للتطوير فقط |
| API Key | ❌ غير مُعرّف | يجب إضافته للإنتاج |
| WhatsApp/SMS | ⏳ جاهز | سيعمل بعد إضافة API Key |
| Lambda Function | ✅ منشور | آخر تحديث: الآن |

---

## 🎯 خطوات التفعيل السريعة

```bash
# 1. إضافة API Key
aws ssm put-parameter \
  --name "/wizgym/prod/OTPIQ_API_KEY" \
  --value "YOUR_KEY_HERE" \
  --type "SecureString" \
  --profile wizgym-prod \
  --region us-east-1

# 2. تعطيل Mock Mode في template.yaml (غيّر OTPIQ_MOCK_MODE إلى 'false')

# 3. إعادة النشر
cd infra/sam && sam build && sam deploy --config-env prod

# 4. اختبار
curl -X POST https://3u10v51mvk.execute-api.us-east-1.amazonaws.com/api/v1/auth/phone/send-otp \
  -H "Content-Type: application/json" \
  -d '{"phoneNumber":"+9647831367435"}'

# 5. تحقق من اللوجز
aws logs tail /aws/lambda/sam-app-WizGymApiFunction-yE1SQSAsdJGg --follow
```

---

## 📞 الدعم - Support

إذا واجهت أي مشاكل:
1. راجع CloudWatch Logs
2. تحقق من [OTP IQ Documentation](https://docs.otpiq.com)
3. تأكد من صحة تكوين AWS Parameter Store

---

**آخر تحديث:** 4 مارس 2026  
**الإصدار:** 1.0.0  
**الحالة:** ✅ جاهز للإنتاج (بعد إضافة API Key)
