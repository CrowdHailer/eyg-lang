# Policy walkthrough

## 00:00 — One policy. Every decision.

Let's build access policies with Gleam and E Y G. We will sign in, create commits, approve changes, and limit inference usage. For every allowed policy decision, the engine will now show its actual proof tree.

## 00:15 — Write the relationship rule

First, write the E Y G rule. Join a user's channel membership with a role permission. Tenant, actor, action, and resource come from the authenticated request. A matching row is the permission proof.

## 00:29 — Choose who can do what

Now write the Gleam grants. Platform members may open the deployments page, change infrastructure files, and approve those changes. These are separate permissions. Unknown paths are denied by default.

## 00:44 — Sign in as Ada

Ada chooses Sign in with Slack. Our mock completes the login flow. The Gleam host checks single use state, browser binding, nonce, workspace, and expiry. Ada then links her GitHub identity.

## 00:59 — Enforce the page permission

Ada belongs to Platform, so deployments returns two hundred. Finance returns four oh three. These results come from the actual E Y G evaluator. The protected data loader runs only after authorization.

## 01:14 — Why Ada is allowed: the page proof

Read the engine generated tree from the leaves upward. The Member fact puts Ada in Platform. The Role Permission fact lets Platform view deployments. Rule zero joins those exact facts and produces Permit. Session checks are performed separately by the host.

## 01:32 — Create a real commit

In an isolated local Git repository, Ada increases the worker replicas from two to three. We inspect the diff, stage the file, and commit. This is a real commit; the main project history is untouched.

## 01:47 — Open the pull request

The mock pull request points to that exact commit. Ada has permission to change infrastructure. But there is no eligible approval yet, so the channel policy check blocks merging.

## 02:00 — An approval must carry permission

Cal approves the pull request. Cal belongs to Finance, not Platform. The approval exists, but it cannot authorize this infrastructure change. The check stays blocked.

## 02:13 — Bea approves the current commit

Bea signs in and approves the current head. She belongs to Platform. Both submitter and reviewer permissions now have proofs, and the mock check succeeds. GitHub must require this check to enforce it.

## 02:28 — Why this PR passes: two permission trees

The passing pull request has two engine generated trees. Ada's membership joins the infrastructure change grant. Bea's membership joins the infrastructure approval grant. The host additionally verifies the linked GitHub identities, the current commit approval, and coverage of every changed path.

## 02:48 — A new commit needs a new approval

Ada creates a second real commit, increasing replicas to four. Bea's earlier approval names the old commit. The current head has changed, so the policy blocks the pull request again.

## 03:01 — Review the updated change

Bea reviews the new commit and approves again. The current head now has an eligible approval, so both permission checks pass.

## 03:11 — New head. Fresh evaluation. Explained allow.

Here are the proof trees returned by the new evaluation. Both memberships and grants still hold. The host now associates Bea's fresh review with the new commit. The same policy facts explain access, while the host enforces commit specific approval.

## 03:29 — Membership controls ongoing access

Now remove Bea from Platform and refresh membership. Reevaluating the same pull request removes her approval's authority. The check fails. Production webhooks or scheduled refreshes must trigger this reevaluation.

## 03:44 — Add an LLM inference quota

Here is a second E Y G policy. Match trusted usage and quota facts for the same workspace, user, endpoint, and billing window. Only permit inference when usage is nonnegative and strictly below the limit.

## 03:59 — Query the model below the limit

Ada has used forty nine of fifty inference requests. The policy allows the next request. Let's inspect the full engine generated proof before forwarding anything to the model.

## 04:12 — Why inference is allowed: facts plus predicates

The quota is fifty and usage is forty nine, for the same user, endpoint, and billing window. Three predicates passed: the action is inference, usage is nonnegative, and forty nine is less than fifty. These are actual recorded guard results, with their bound values.

## 04:31 — At the limit, there is no permit tree

Once the allowed request is reserved, usage reaches fifty. Fifty is not less than fifty, so the next call has no Permit row and no successful proof tree. The gateway must reserve usage atomically before calling the model.

## 04:47 — Try it, then connect the adapters

Proof trees now come from the Datalog engine, alongside its ordinary answers. Run the Gleam examples to inspect them. Slack and GitHub are still mocked, and the interface is illustrated. The video includes captured proof data and a readable transcript.
