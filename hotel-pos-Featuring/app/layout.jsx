import "./globals.css";

export const metadata = {
  title: "Bingo Hotel | Order Book",
  description: "Hotel food orders and daily accountability",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
