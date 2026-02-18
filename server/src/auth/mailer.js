import nodemailer from "nodemailer";

let transporter;

const getTransporter = () => {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST || "smtp.gmail.com",
      port: Number(process.env.SMTP_PORT || 587),
      secure: Number(process.env.SMTP_PORT) === 465,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    });
  }
  return transporter;
};

export async function sendVerificationEmail(email, token) {
  const url = `${process.env.SERVER_URL}/api/auth/verify-email?token=${token}`;
  const from = process.env.SMTP_FROM || "Zipp <noreply@sinisterswiss.ch>";

  await getTransporter().sendMail({
    from,
    to: email,
    subject: "Verify your Zipp email address",
    text: `Click the link below to verify your email:\n\n${url}\n\nThis link expires in 24 hours.`,
    html: `
      <div style="font-family:sans-serif;max-width:480px;margin:0 auto">
        <h2 style="color:#7C3AED">Welcome to Zipp</h2>
        <p>Click the button below to verify your email address.</p>
        <a href="${url}" style="display:inline-block;padding:12px 24px;background:linear-gradient(135deg,#7C3AED,#06B6D4);color:#fff;text-decoration:none;border-radius:8px;font-weight:600">
          Verify Email
        </a>
        <p style="color:#888;font-size:12px;margin-top:24px">This link expires in 24 hours. If you didn't create a Zipp account, you can safely ignore this email.</p>
      </div>
    `,
  });
}
