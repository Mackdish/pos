import "./globals.css";

export const metadata = {
  title: "Bingo Hotel | Hotel & Restaurant POS",
  description: "Secure hotel and restaurant point-of-sale operations, payments and reporting.",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
