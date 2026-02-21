import { config } from '../config.js';

const BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email';

interface BrevoEmailPayload {
  sender: { name: string; email: string };
  to: { email: string; name?: string }[];
  subject: string;
  htmlContent: string;
}

async function sendEmail(payload: BrevoEmailPayload): Promise<boolean> {
  try {
    const response = await fetch(BREVO_API_URL, {
      method: 'POST',
      headers: {
        'accept': 'application/json',
        'api-key': config.brevoApiKey,
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorData = await response.text();
      console.error('Brevo API error:', response.status, errorData);
      return false;
    }

    return true;
  } catch (error) {
    console.error('Failed to send email via Brevo:', error);
    return false;
  }
}

export async function sendVerificationEmail(to: string, token: string): Promise<boolean> {
  const verifyUrl = `${config.appUrl}/api/auth/verify-email?token=${token}`;

  return sendEmail({
    sender: {
      name: config.emailFromName,
      email: config.emailFrom,
    },
    to: [{ email: to }],
    subject: 'Nanochat - 验证您的邮箱',
    htmlContent: `
      <div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">
        <h1 style="color: #2563eb;">欢迎加入 Nanochat</h1>
        <p>请点击下方按钮验证您的邮箱地址：</p>
        <a href="${verifyUrl}" 
           style="display: inline-block; background: #2563eb; color: white; 
                  padding: 12px 24px; text-decoration: none; border-radius: 8px;
                  font-size: 16px; margin: 16px 0;">
          验证邮箱
        </a>
        <p style="color: #666; font-size: 14px;">
          如果按钮无法点击，请复制以下链接到浏览器：<br>
          <a href="${verifyUrl}">${verifyUrl}</a>
        </p>
        <hr style="border: none; border-top: 1px solid #eee; margin: 24px 0;">
        <p style="color: #999; font-size: 12px;">
          此邮件由 Nanochat 自动发送，请勿回复。
        </p>
      </div>
    `,
  });
}
