#!/usr/bin/env node
// data/update-solution-mapping.mjs
//
// Downloads the latest Content Hub solution mapping CSVs from the
// Azure-Sentinel Solutions Analyzer and regenerates the static JSON
// lookup used by the PowerShell report and the web app solution matcher.
//
// Usage:  node data/update-solution-mapping.mjs
//
// Outputs:
//   data/solution-mapping.json          (this folder - used by the PS script)
//   src/lib/data/solution-mapping.json  (web app - if the repo root is reachable)

import { writeFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOCAL_OUTPUT = join(__dirname, 'solution-mapping.json');
const WEBAPP_OUTPUT = join(__dirname, '..', '..', '..', 'src', 'lib', 'data', 'solution-mapping.json');

const BASE =
  'https://raw.githubusercontent.com/Azure/Azure-Sentinel/master/Tools/Solutions%20Analyzer';

async function fetchCsv(filename) {
  const res = await fetch(`${BASE}/${filename}`);
  if (!res.ok) throw new Error(`Failed to fetch ${filename}: ${res.status}`);
  return res.text();
}

function parseCsvRow(row) {
  const fields = [];
  let inQuote = false;
  let current = '';
  for (let i = 0; i < row.length; i++) {
    const ch = row[i];
    if (ch === '"') {
      inQuote = !inQuote;
      continue;
    }
    if (ch === ',' && !inQuote) {
      fields.push(current);
      current = '';
      continue;
    }
    current += ch;
  }
  fields.push(current);
  return fields;
}

async function main() {
  console.log('Fetching simplified mapping...');
  const simplified = await fetchCsv('solutions_connectors_tables_mapping_simplified.csv');

  console.log('Fetching full mapping for solution metadata...');
  const full = await fetchCsv('solutions_connectors_tables_mapping.csv');

  // Build table -> unique solution names
  const tablesToSolutions = {};
  const simplifiedLines = simplified.trim().split('\n').slice(1);
  for (const line of simplifiedLines) {
    const match = line.match(/"([^"]*)","([^"]*)","([^"]*)"/);
    if (!match) continue;
    const [, solutionName, , tableName] = match;
    if (!tablesToSolutions[tableName]) {
      tablesToSolutions[tableName] = new Set();
    }
    tablesToSolutions[tableName].add(solutionName);
  }

  // Convert sets to sorted arrays
  for (const key of Object.keys(tablesToSolutions)) {
    tablesToSolutions[key] = [...tablesToSolutions[key]].sort();
  }

  // Extract solution metadata from full mapping
  const solutionMetadata = {};
  const fullLines = full.trim().split('\n');
  for (let i = 1; i < fullLines.length; i++) {
    const fields = parseCsvRow(fullLines[i]);
    const solutionName = fields[1];
    if (!solutionName || solutionMetadata[solutionName]) continue;
    solutionMetadata[solutionName] = {
      publisherId: fields[4] || undefined,
      offerId: fields[5] || undefined,
      githubUrl: fields[3] || undefined,
    };
  }

  const output = {
    generatedAt: new Date().toISOString().split('T')[0],
    sourceUrl: 'https://github.com/Azure/Azure-Sentinel/tree/master/Tools/Solutions%20Analyzer',
    tableCount: Object.keys(tablesToSolutions).length,
    solutionCount: Object.keys(solutionMetadata).length,
    tablesToSolutions,
    solutionMetadata,
  };

  const json = JSON.stringify(output, null, 2) + '\n';

  writeFileSync(LOCAL_OUTPUT, json);
  console.log(`\nWritten to ${LOCAL_OUTPUT}`);

  if (existsSync(dirname(WEBAPP_OUTPUT))) {
    writeFileSync(WEBAPP_OUTPUT, json);
    console.log(`Written to ${WEBAPP_OUTPUT}`);
  } else {
    console.log(`Skipped web app output (${dirname(WEBAPP_OUTPUT)} not found)`);
  }

  console.log(`  Tables:    ${output.tableCount}`);
  console.log(`  Solutions: ${output.solutionCount}`);
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
