#!/usr/bin/env node
/*
 * Installer for @hephaestus-workers/cc-statusline
 *
 * Usage:
 *   npx @hephaestus-workers/cc-statusline              install
 *   npx @hephaestus-workers/cc-statusline --uninstall  uninstall
 */
"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");

const claudeDir = path.join(os.homedir(), ".claude");
const targetScript = path.join(claudeDir, "statusline.sh");
const backupScript = targetScript + ".backup";
const settingsFile = path.join(claudeDir, "settings.json");
const sourceScript = path.join(__dirname, "statusline.sh");
const packageFile = path.join(__dirname, "..", "package.json");

const VERSION_PLACEHOLDER = "__CC_STATUSLINE_VERSION__";

function packageVersion() {
  try {
    return JSON.parse(fs.readFileSync(packageFile, "utf8")).version || "";
  } catch (err) {
    return "";
  }
}

function readSettings() {
  if (!fs.existsSync(settingsFile)) {
    return {};
  }
  const raw = fs.readFileSync(settingsFile, "utf8");
  if (raw.trim() === "") {
    return {};
  }
  try {
    return JSON.parse(raw);
  } catch (err) {
    console.error(`Error: could not parse ${settingsFile} as JSON: ${err.message}`);
    console.error("Aborting without touching your settings. Please fix the file and retry.");
    process.exit(1);
  }
}

function writeSettings(settings) {
  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n", "utf8");
}

// Every release of this fork names itself, and the upstream statusline it was
// forked from never does, so this tells our own file from a genuinely
// pre-existing one. Unreadable files count as not ours, which errs towards
// keeping whatever is there.
function isOurScript(file) {
  try {
    return fs.readFileSync(file, "utf8").includes("cc-statusline");
  } catch (err) {
    return false;
  }
}

function makeExecutable(file) {
  try {
    fs.chmodSync(file, 0o755);
  } catch (err) {
    // chmod is not meaningful on Windows; ignore
  }
}

// bash reads a script from disk as it goes, so overwriting the file a status
// line run is currently executing can corrupt that run. Writing a temp file
// and renaming it into place gives the new content a fresh inode, leaving any
// run already in flight to finish against the old one.
function writeScriptAtomically(file, content) {
  const tmp = `${file}.tmp-${process.pid}`;
  try {
    fs.writeFileSync(tmp, content, "utf8");
    makeExecutable(tmp);
    fs.renameSync(tmp, file);
  } catch (err) {
    try {
      fs.unlinkSync(tmp);
    } catch (cleanupErr) {
      // nothing to clean up
    }
    fs.writeFileSync(file, content, "utf8");
    makeExecutable(file);
  }
}

function install() {
  // Validate settings.json first so we never leave things half-installed
  const settings = readSettings();

  fs.mkdirSync(claudeDir, { recursive: true });

  // Upgrading means running the installer again, so the backup must only ever
  // hold a statusline that is not one of ours. Backing up our own file would
  // make --uninstall restore an old cc-statusline instead of removing it, and
  // installers before v1.2.1 did exactly that on the first upgrade of a
  // machine that had no statusline beforehand - clear those out on the way.
  if (fs.existsSync(backupScript) && isOurScript(backupScript)) {
    fs.unlinkSync(backupScript);
    console.log(`Discarded ${backupScript}: it held cc-statusline itself, not a pre-install statusline`);
  }
  if (fs.existsSync(targetScript)) {
    if (fs.existsSync(backupScript)) {
      console.log(`Keeping the existing backup at ${backupScript}`);
    } else if (!isOurScript(targetScript)) {
      fs.copyFileSync(targetScript, backupScript);
      console.log(`Backed up existing statusline to ${backupScript}`);
    }
  }

  // Normalize line endings so the script always runs under bash,
  // even when npm/git checked it out with CRLF on Windows
  let content = fs.readFileSync(sourceScript, "utf8").replace(/\r\n/g, "\n");
  // Stamp the version so the installed copy can tell whether it is behind.
  // A copy running straight from the repo keeps the placeholder instead.
  content = content.split(VERSION_PLACEHOLDER).join(packageVersion());
  writeScriptAtomically(targetScript, content);

  settings.statusLine = {
    type: "command",
    command: "~/.claude/statusline.sh",
    padding: 0,
  };
  writeSettings(settings);

  console.log(`Installed ${targetScript}`);
  console.log(`Updated ${settingsFile} (statusLine)`);
  console.log("");
  console.log("Done! Restart Claude Code to see the new statusline.");
  console.log("");
  console.log("Requirements: jq, curl, git (on Windows, bash via Git for Windows).");
  console.log("Uninstall anytime with: npx @hephaestus-workers/cc-statusline --uninstall");
}

function uninstall() {
  if (fs.existsSync(backupScript)) {
    // Same reason as on install: swap the file in rather than overwrite it
    try {
      fs.renameSync(backupScript, targetScript);
    } catch (err) {
      fs.copyFileSync(backupScript, targetScript);
      fs.unlinkSync(backupScript);
    }
    makeExecutable(targetScript);
    console.log(`Restored previous statusline from ${backupScript}`);
  } else {
    if (fs.existsSync(targetScript)) {
      fs.unlinkSync(targetScript);
      console.log(`Removed ${targetScript}`);
    }
    if (fs.existsSync(settingsFile)) {
      const settings = readSettings();
      if (settings.statusLine) {
        delete settings.statusLine;
        writeSettings(settings);
        console.log(`Removed statusLine from ${settingsFile}`);
      }
    }
  }
  console.log("Uninstall complete. Restart Claude Code to apply.");
}

if (process.argv.includes("--uninstall")) {
  uninstall();
} else {
  install();
}
