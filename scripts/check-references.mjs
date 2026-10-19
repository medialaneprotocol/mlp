#!/usr/bin/env node
// Checks the specification's cross-references.
//
// Every "§N.N" in the specification, and every "MLP spec §N.N" in the
// reference implementations, must name a section that exists. A reference
// that points at nothing is a dead cross-reference: it sends a reader
// looking for a rule that is not there, and it hides the fact that the
// rule was never written.
//
// Usage:
//   node scripts/check-references.mjs                 # check the specification
//   node scripts/check-references.mjs --impl <dir>    # also check an implementation
//
// The checker is deliberately strict: it resolves a reference against the
// headings that actually exist, and it fails on the ones that do not.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const specRoot = path.resolve(here, "..", "spec");

/** Every section the specification defines, as a dotted number. */
function collectSections() {
  const sections = new Set();
  const files = fs
    .readdirSync(specRoot)
    .filter((name) => name.endsWith(".md"))
    .sort();
  for (const file of files) {
    const text = fs.readFileSync(path.join(specRoot, file), "utf8");
    for (const line of text.split("\n")) {
      const heading = /^#{1,3}\s+(\d+(?:\.\d+)*)\b/.exec(line);
      if (heading) {
        sections.add(heading[1]);
      }
    }
  }
  return sections;
}

/** Every section a file refers to. */
function collectReferences(text) {
  const found = [];
  const pattern = /§(\d+(?:\.\d+)*)/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    found.push({ section: match[1], index: match.index });
  }
  return found;
}

/** The line number of an index in a text. */
function lineOf(text, index) {
  let line = 1;
  for (let i = 0; i < index; i += 1) {
    if (text.charCodeAt(i) === 10) {
      line += 1;
    }
  }
  return line;
}

/** Whether a reference resolves: the section exists, or a prefix of it does. */
function resolves(section, sections) {
  if (sections.has(section)) {
    return true;
  }
  // A reference to a parent section resolves when the child exists.
  const parts = section.split(".");
  while (parts.length > 1) {
    parts.pop();
    if (sections.has(parts.join("."))) {
      return true;
    }
  }
  return false;
}

let failures = 0;
const sections = collectSections();

console.log(`check-references: ${sections.size} sections defined`);

for (const file of fs.readdirSync(specRoot).filter((n) => n.endsWith(".md")).sort()) {
  const text = fs.readFileSync(path.join(specRoot, file), "utf8");
  for (const reference of collectReferences(text)) {
    if (resolves(reference.section, sections)) {
      continue;
    }
    failures += 1;
    console.log(
      `FAIL spec/${file}:${lineOf(text, reference.index)} — §${reference.section} does not exist`,
    );
  }
}

const implRoots = [];
for (let index = 0; index < process.argv.length; index += 1) {
  if (process.argv[index] === "--impl" && process.argv[index + 1]) {
    implRoots.push(path.resolve(process.argv[index + 1]));
    index += 1;
  }
}
for (const implRoot of implRoots) {
  const patterns = [/\.(rs|ts|tsx|js|mjs|md)$/];
  const walk = (directory) => {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      if (entry.name === "target" || entry.name === "node_modules" || entry.name === ".git") {
        continue;
      }
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (patterns.some((pattern) => pattern.test(entry.name))) {
        const text = fs.readFileSync(full, "utf8");
        for (const reference of collectReferences(text)) {
          if (!resolves(reference.section, sections)) {
            failures += 1;
            console.log(
              `FAIL ${path.relative(implRoot, full)}:${lineOf(text, reference.index)} — §${reference.section} does not exist`,
            );
          }
        }
      }
    }
  };
  walk(implRoot);
}

if (failures > 0) {
  console.log(`check-references: ${failures} dangling reference(s)`);
  process.exit(1);
}
console.log("check-references: every reference resolves");
