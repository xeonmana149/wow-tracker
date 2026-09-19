import type { Metadata } from "next";
import { Cinzel, Source_Sans_3 } from "next/font/google";
import "./globals.css";
import "./theme.css";
import SiteNav from "./SiteNav";
import LaunchCountdown from "./LaunchCountdown";

const heading = Cinzel({
  subsets: ["latin"],
  variable: "--font-heading",
});

const body = Source_Sans_3({
  subsets: ["latin"],
  variable: "--font-body",
});

export const metadata: Metadata = {
  title: "WoW Forever Tracker",
  description: "Track your WoW Forever characters, gear and talents with your friends.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${heading.variable} ${body.variable} antialiased`}>
        <div className="mx-auto max-w-[1500px] px-4 pt-4 md:px-6 md:pt-6">
          <SiteNav />
          <LaunchCountdown />
        </div>
        {children}
      </body>
    </html>
  );
}