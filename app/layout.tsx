import type { Metadata } from "next";
import Image from "next/image";
import { Cinzel, Source_Sans_3 } from "next/font/google";
import "./globals.css";
import "./theme.css";
import SiteNav from "./SiteNav";
import LaunchCountdown from "./LaunchCountdown";
import ActivitySidebar from "./ActivitySidebar";

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
        {/* The background picture. public/background.jpg, blurred and darkened in theme.css */}
        <div className="site-bg" aria-hidden="true">
          <Image
            src="/background.jpg"
            alt=""
            fill
            priority
            sizes="100vw"
            className="site-bg-img"
          />
        </div>

        <div className="mx-auto max-w-[1500px] px-4 pt-4 md:px-6 md:pt-6">
          <SiteNav />
          <LaunchCountdown />
        </div>
        {children}

        {/* Floating activity feed, docked to the right on wide screens only -
            lives here (not inside any one page) so it's the same on every
            tab, and it's `fixed` positioned so it never affects the width
            or centering of the content above. */}
        <ActivitySidebar />
      </body>
    </html>
  );
}
