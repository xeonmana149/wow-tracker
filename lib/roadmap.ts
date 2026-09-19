// Blizzard's 2026 | 2027 World of Warcraft: Forever roadmap.
// Blizzard names the seasons for the northern hemisphere. Here they're renamed for
// Australia, with Blizzard's own name kept underneath so it still lines up with their picture.
// Content and timing are subject to change, so edit the dates here if they move.

export type Milestone = {
  title: string;
  date?: string; // how the date is shown
  start?: string; // YYYY-MM-DD, used to work out what's live and what's next
  end?: string; // YYYY-MM-DD, for date ranges
  note?: string;
  items?: string[];
};

export type Season = { name: string; official?: string; milestones: Milestone[] };

export const ROADMAP: Season[] = [
  {
    name: "Spring 2026",
    official: "Blizzard: Autumn 2026",
    milestones: [
      {
        title: "Beta",
        date: "Sep 17 – Oct 22",
        start: "2026-09-17",
        end: "2026-10-22",
        items: ["Play up to level 30"],
      },
      {
        title: "Early name reservation & character creation",
        date: "Oct 27",
        start: "2026-10-27",
      },
      {
        title: "World of Warcraft: Forever launches",
        date: "Nov 4",
        start: "2026-11-04",
        note: "3:00 pm PST",
      },
    ],
  },
  {
    name: "Summer 2026–27",
    official: "Blizzard: Winter",
    milestones: [
      {
        title: "Raids unlock",
        date: "Dec 9",
        start: "2026-12-09",
        items: ["Barrow Deeps (10 player)", "Hyjal Summit (20 player)", "Onyxia's Lair (40 player)"],
      },
      {
        title: "World of Warcraft: Forever Hardcore launches",
        note: "Date not announced yet",
      },
    ],
  },
  {
    name: "Autumn 2027",
    official: "Blizzard: Spring 2027",
    milestones: [
      {
        title: "Major updates",
        items: [
          "2 new raids (10 player, 20 player)",
          "2 new dungeons",
          "New quests and playable area",
          "New legendary questline",
          "PvP season refresh",
        ],
      },
    ],
  },
  {
    name: "Winter 2027",
    official: "Blizzard: Summer 2027",
    milestones: [
      {
        title: "Major updates",
        items: [
          "Revamped iconic raid",
          "New raid",
          "Expanded world content",
          "2 new dungeons",
          "PvP season refresh",
          "Professions and Legacy updates",
        ],
      },
    ],
  },
];

// When World of Warcraft: Forever launches: 4 November 2026, 3:00 pm PST.
// If Blizzard moves it, change this one line and the countdown follows.
export const LAUNCH_TIME = "2026-11-04T15:00:00-08:00";