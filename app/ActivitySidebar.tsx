import ActivityFeed from "./ActivityFeed";

// Docks the activity feed to the right edge of the screen as its own
// floating panel, completely separate from each page's own centered
// content - it never shrinks or pushes the main column around. It only
// shows up once there's enough spare room beside a centered page (screens
// 1536px and wider), and simply disappears below that rather than ever
// cramping anything.
//
// `top-20` assumes roughly a normal header's height above it - nudge that
// (and the matching number inside the calc() below) if it sits too high
// or too low under your actual header.
export default function ActivitySidebar() {
  return (
    <div className="fixed right-4 top-20 z-30 hidden h-[calc(100vh-6rem)] w-80 2xl:block">
      <ActivityFeed />
    </div>
  );
}
