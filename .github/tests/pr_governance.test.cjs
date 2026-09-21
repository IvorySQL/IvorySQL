const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

// Exercise the script used by github-script, rather than a copy of its parser.
const workflowPath = process.env.PR_GOVERNANCE_WORKFLOW || path.join(__dirname, '../workflows/pr_governance.yml');
const workflow = readFileSync(workflowPath, 'utf8');
const scriptBody = workflow.split(/^\s+script: \|\r?\n/m)[1];
assert.ok(scriptBody, 'The governance workflow must contain an inline script');
const script = new vm.Script(`(async () => {\n${scriptBody.replace(/^ {12}/gm, '')}\n})()`);

async function runPolicy(body, { pullRequest = false, missingIssue = false, manualIssue } = {}) {
  const requests = [];
  const failures = [];
  let report;
  const core = {
    setFailed(message) { failures.push(message); },
    summary: {
      addRaw(value) { report = value; return this; },
      async write() {},
    },
  };
  const github = {
    rest: {
      issues: {
        async get({ owner, repo, issue_number }) {
          requests.push({ owner, repo, issue_number });
          if (missingIssue) {
            throw Object.assign(new Error('Not Found'), { status: 404 });
          }
          return {
            data: {
              node_id: `${owner}/${repo}#${issue_number}`,
              number: issue_number,
              ...(pullRequest ? { pull_request: {} } : {}),
            },
          };
        },
      },
      pulls: { listReviews() {} },
    },
    async paginate() { return [{ state: 'APPROVED' }]; },
    async graphql() {
      return {
        repository: {
          issues: {
            nodes: manualIssue ? [{
              number: manualIssue,
              timelineItems: {
                nodes: [{
                  __typename: 'ConnectedEvent',
                  source: { __typename: 'PullRequest', id: 'PR_node' },
                  subject: {
                    __typename: 'Issue',
                    id: `IvorySQL/IvorySQL#${manualIssue}`,
                    number: manualIssue,
                  },
                }],
              },
            }] : [],
            pageInfo: { hasNextPage: false, endCursor: null },
          },
        },
      };
    },
  };
  const context = {
    repo: { owner: 'IvorySQL', repo: 'IvorySQL' },
    payload: {
      pull_request: {
        node_id: 'PR_node', number: 456, body, title: 'Fix governance',
        changed_files: 2, additions: 10, deletions: 1,
      },
    },
  };

  await script.runInNewContext({ context, github, core });
  return { requests, failures, report };
}

for (const body of [
  'Fixes https://github.com/IvorySQL/IvorySQL/issues/123',
  'Fixes [the issue](https://github.com/IvorySQL/IvorySQL/issues/123)',
  'Fixes <https://github.com/IvorySQL/IvorySQL/issues/123>',
  'https://github.com/IvorySQL/IvorySQL/issues/123#issuecomment-456',
  'Fixes #123',
  'Fixes IvorySQL/IvorySQL#123',
]) {
  test(`accepts issue reference: ${body}`, async () => {
    const result = await runPolicy(body);
    assert.deepEqual(result.requests, [{ owner: 'IvorySQL', repo: 'IvorySQL', issue_number: 123 }]);
    assert.deepEqual(result.failures, []);
    assert.match(result.report, /Total linked issues accepted by policy: 1/);
  });
}

for (const body of [
  '',
  'No linked issue',
  'https://example.com/IvorySQL/IvorySQL/issues/123',
  'https://github.com.example.com/IvorySQL/IvorySQL/issues/123',
  'https://github.com/IvorySQL/IvorySQL/pull/123',
  'https://github.com/IvorySQL/IvorySQL/issues/not-a-number',
  'https://github.com/IvorySQL/IvorySQL/issues/0',
  'https://github.com/IvorySQL/IvorySQL/issues/9007199254740993',
  '#0',
  '#9007199254740993',
  'IvorySQL/IvorySQL#0',
  'IvorySQL/IvorySQL#9007199254740993',
]) {
  test(`rejects body without an issue reference: ${JSON.stringify(body)}`, async () => {
    const result = await runPolicy(body);
    assert.deepEqual(result.requests, []);
    assert.match(result.failures[0], /PR must reference at least one issue/);
  });
}

test('preserves cross-repository issue diagnostics', async () => {
  const result = await runPolicy('https://github.com/other/project/issues/123');
  assert.deepEqual(result.requests, [{ owner: 'other', repo: 'project', issue_number: 123 }]);
  assert.deepEqual(result.failures, []);
  assert.match(result.report, /Cross-repository issue references were found/);
});

test('counts repeated URL, shorthand and sidebar references as one linked issue', async () => {
  const url = 'https://github.com/IvorySQL/IvorySQL/issues/123';
  const result = await runPolicy(`${url} ${url} #123`, { manualIssue: 123 });
  assert.equal(result.requests.length, 3);
  assert.deepEqual(result.failures, []);
  assert.match(result.report, /Total linked issues accepted by policy: 1/);
});

test('rejects a URL whose issue API response identifies a pull request', async () => {
  const result = await runPolicy('https://github.com/IvorySQL/IvorySQL/issues/123', { pullRequest: true });
  assert.equal(result.requests.length, 1);
  assert.match(result.failures[0], /PR must reference at least one issue/);
});

test('warns and fails when the issue URL returns 404', async () => {
  const result = await runPolicy('https://github.com/IvorySQL/IvorySQL/issues/123', { missingIssue: true });
  assert.equal(result.requests.length, 1);
  assert.match(result.report, /Could not validate whether IvorySQL\/IvorySQL#123 is an issue or a pull request/);
  assert.match(result.failures[0], /PR must reference at least one issue/);
});

test('still accepts a same-repository sidebar link without a body reference', async () => {
  const result = await runPolicy('', { manualIssue: 123 });
  assert.deepEqual(result.requests, []);
  assert.deepEqual(result.failures, []);
  assert.match(result.report, /Same-repository manual-linked issues detected: 1/);
});
