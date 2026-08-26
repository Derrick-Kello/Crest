import { NextResponse } from "next/server";

/**
 * The single place the installer URL lives. Every Download button on the site
 * points at /download, so shipping a new build never means editing the site.
 *
 * The `releases/latest/download/<asset>` form is a permalink: GitHub resolves it
 * to whichever release is marked latest, so the version never appears here.
 */
const LATEST_DMG =
  "https://github.com/Derrick-Kello/Crest/releases/latest/download/Crest.dmg";

export function GET() {
  // 302, not 301: the target moves with every release and must not be cached.
  return NextResponse.redirect(LATEST_DMG, 302);
}
