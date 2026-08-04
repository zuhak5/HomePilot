import assert from "node:assert/strict";
import test from "node:test";
import {
  buildHistoricalModel,
  createBuildSnapshot,
  detectBuildTransition,
  formatRemainingTime,
  isVisibleBuildStep,
  median,
  selectActiveRun,
} from "../download-site/build-status.js";

const START = Date.parse("2026-08-04T12:00:00Z");

function step(name, offset, duration, status = "completed") {
  return {
    name,
    status,
    conclusion: status === "completed" ? "success" : null,
    started_at: new Date(START + offset * 1000).toISOString(),
    completed_at: status === "completed"
      ? new Date(START + (offset + duration) * 1000).toISOString()
      : null,
  };
}

function successfulJob(multiplier = 1) {
  return {
    name: "Build signed production APK",
    status: "completed",
    conclusion: "success",
    steps: [
      step("Set up job", 0, 1),
      step("Check out repository", 1, 10 * multiplier),
      step("Build and test production APK", 11, 300 * multiplier),
      step("Publish GitHub Release", 311, 30 * multiplier),
      step("Post Check out repository", 341, 1),
      step("Complete job", 342, 1),
    ],
  };
}

test("median is outlier resistant", () => {
  assert.equal(median([10, 11, 12, 1000, 13]), 12);
});

test("hidden Actions housekeeping steps are excluded", () => {
  assert.equal(isVisibleBuildStep({ name: "Set up job" }), false);
  assert.equal(isVisibleBuildStep({ name: "Post Check out repository" }), false);
  assert.equal(isVisibleBuildStep({ name: "Build and test production APK" }), true);
});

test("history model calculates per-step and total medians", () => {
  const model = buildHistoricalModel([
    successfulJob(1),
    successfulJob(1.1),
    successfulJob(0.9),
  ]);
  assert.equal(model.sampleCount, 3);
  assert.equal(model.stepOrder.length, 3);
  assert.ok(model.stepMedians["Build and test production APK"] >= 299);
  assert.ok(model.totalMedianSeconds > 330);
});

test("active run selection prefers a running build over a newer queued build", () => {
  const run = selectActiveRun([
    { id: 2, status: "queued", head_branch: "main", event: "workflow_dispatch", created_at: "2026-08-04T12:05:00Z" },
    { id: 1, status: "in_progress", head_branch: "main", event: "workflow_dispatch", created_at: "2026-08-04T12:00:00Z" },
  ]);
  assert.equal(run.id, 1);
});

test("snapshot reports steps remaining and a history-based ETA", () => {
  const history = buildHistoricalModel(Array.from({ length: 5 }, () => successfulJob(1)));
  const run = {
    id: 42,
    run_number: 17,
    status: "in_progress",
    head_branch: "main",
    event: "workflow_dispatch",
    html_url: "https://github.com/zuhak5/HomePilot/actions/runs/42",
  };
  const job = {
    name: "Build signed production APK",
    status: "in_progress",
    started_at: new Date(START).toISOString(),
    steps: [
      step("Check out repository", 0, 10),
      step("Build and test production APK", 10, 0, "in_progress"),
      { name: "Publish GitHub Release", status: "queued", conclusion: null, started_at: null, completed_at: null },
    ],
  };
  const snapshot = createBuildSnapshot(run, job, history, { now: START + 70_000 });
  assert.equal(snapshot.completedCount, 1);
  assert.equal(snapshot.remainingCount, 2);
  assert.equal(snapshot.currentStepName, "Build and test production APK");
  assert.ok(snapshot.estimatedSeconds > 200);
  assert.equal(snapshot.estimateConfidence, "high");
});

test("transition announces a completed step and next step", () => {
  const previous = {
    runId: 42,
    runNumber: 17,
    status: "in_progress",
    currentStepName: "Check out repository",
    completedStepNames: [],
    totalSteps: 3,
    remainingCount: 3,
    estimatedSeconds: 400,
  };
  const current = {
    ...previous,
    currentStepName: "Build and test production APK",
    completedStepNames: ["Check out repository"],
    remainingCount: 2,
    estimatedSeconds: 330,
  };
  const transition = detectBuildTransition(previous, current);
  assert.match(transition.message, /Completed Check out repository/);
  assert.match(transition.message, /Now running Build and test production APK/);
  assert.match(transition.message, /2 steps remain/);
});

test("remaining time formatting is concise", () => {
  assert.equal(formatRemainingTime(30), "Less than a minute");
  assert.equal(formatRemainingTime(600), "About 10 minutes");
  assert.equal(formatRemainingTime(5_400), "About 1 hr 30 min");
});
