import type {Metadata} from 'next';
import './globals.css'; // Global styles

export const metadata: Metadata = {
  title: 'Wololo Desk',
  description: 'Competitive RTS coach simulator with civilization drafts, tactical prep, and best-of-5 match resolution.',
  openGraph: {
    title: 'Wololo Desk',
    description: 'Competitive RTS coach simulator with civilization drafts, tactical prep, and best-of-5 match resolution.',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Wololo Desk',
    description: 'Competitive RTS coach simulator with civilization drafts, tactical prep, and best-of-5 match resolution.',
  },
};

export default function RootLayout({children}: {children: React.ReactNode}) {
  return (
    <html lang="en">
      <body suppressHydrationWarning>{children}</body>
    </html>
  );
}
