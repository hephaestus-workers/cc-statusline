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

function makeExecutable(file) {
  try {
    fs.chmodSync(file, 0o755);
  } catch (err) {
    // chmod is not meaningful on Windows; ignore
  }
}

function install() {
  // Validate settings.json first so we never leave things half-installed
  const settings = readSettings();

  fs.mkdirSync(claudeDir, { recursive: true });

  // Upgrading means running the installer again, so only ever back up the
  // statusline that was there before the first install
  if (fs.existsSync(targetScript)) {
    if (fs.existsSync(backupScript)) {
      console.log(`Keeping the existing backup at ${backupScript}`);
    } else {
      fs.copyFileSync(targetScript, backupScript);
      console.log(`Backed up existing statusline to ${backupScript}`);
    }
  }

  // Normalize line endings so the script always runs under bash,
  // even when npm/git checked it out with CRLF on Windows
  const content = fs.readFileSync(sourceScript, "utf8").replace(/\r\n/g, "\n");
  fs.writeFileSync(targetScript, content, "utf8");
  makeExecutable(targetScript);

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
    fs.copyFileSync(backupScript, targetScript);
    fs.unlinkSync(backupScript);
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
