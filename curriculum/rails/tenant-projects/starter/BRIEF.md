# Repair Tenant Authorization

You joined a team after a customer reported seeing another organization’s projects. The repository boots and endpoints exist, but the implementation trusts request parameters and leaks data. Repair it without changing the API below.

## Existing repository
Read routes, controller, models, schema, and visible tests first. Users belong to one organization and have a unique api_token and role (viewer or editor). Projects belong to an organization. The test fixtures create all users and projects; no signup or token-creation endpoint is required. Tokens are fictional exercise credentials.

## Contract
Authenticate every request with exactly `Authorization: Bearer <api_token>`. Unknown/missing tokens and malformed authorization return 401. Organization identity and role come from the authenticated user, never from headers or request parameters.

GET /projects returns 200 with the caller’s projects ordered by ascending id. GET /projects/:id returns one project or 404. Missing, malformed, nonpositive, or other-organization IDs all return 404, including on update. Query parameters cannot select another organization.

PATCH /projects/:id accepts a JSON object under project with a name field. Only editors may update their own organization's projects; viewers receive 403 for an existing own project. Resolve ownership before role checks, so a viewer requesting another tenant’s ID still receives 404. A name must be a nonblank string of at most 80 characters. Missing/wrong-shaped envelopes or invalid names return 422 and persist nothing. Unknown attributes (including organization_id and id) must be ignored. Missing name is invalid. Valid updates return 200.

Project objects contain exactly id, name, organization_id. Every failure returns JSON `{ "errors": { "base": ["message"] } }` or field errors with nonempty arrays. Exact wording is not graded. All successful/error responses use JSON.

## Working under pressure
First reproduce the cross-tenant lookup, then protect a vertical slice. Preserve working own-tenant behavior while adding failure paths. You have 55 minutes; reserve five for negative tests and a handoff.

## Out of scope
No OAuth, encryption scheme, token rotation, memberships across organizations, create/delete endpoint, UI, or external services. Discuss revocation and database constraints in the follow-up, rather than building them.

## Handoff
Explain the source of tenant identity, where authorization is enforced, which tests changed your implementation, and what you would investigate before deploying a real incident fix.
