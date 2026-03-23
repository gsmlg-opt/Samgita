# Samgita REST API Documentation

## Overview

The Samgita REST API provides programmatic access to project management, task execution, agent monitoring, and system configuration. All endpoints return JSON responses and follow RESTful conventions.

**Base URL:** `http://localhost:3110/api`

**Rate Limiting:** 100 requests per 60 seconds per IP address

**Authentication:** API keys configured via `config :samgita, :api_keys`. When empty (`[]`), all requests pass through (default for dev/test).

## Table of Contents

- [Public Endpoints](#public-endpoints)
- [Project Management](#project-management)
- [PRD Management](#prd-management)
- [Task Management](#task-management)
- [Agent Runs](#agent-runs)
- [Webhooks](#webhooks)
- [Notifications](#notifications)
- [Feature Flags](#feature-flags)
- [Error Responses](#error-responses)
- [Webhook Payloads](#webhook-payloads)

---

## Public Endpoints

These endpoints do not require authentication and bypass rate limiting.

### Health Check

**GET** `/api/health`

Returns system health status.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-03T14:23:45Z"
}
```

### System Information

**GET** `/api/info`

Returns system metadata and version information.

**Response:**
```json
{
  "version": "0.1.0",
  "elixir_version": "1.17.0",
  "otp_version": "27.0",
  "postgres_version": "14.10",
  "provider": "ClaudeCode",
  "agent_types": 37,
  "active_projects": 5
}
```

---

## Project Management

### List Projects

**GET** `/api/projects`

Returns all projects with pagination.

**Query Parameters:**
- `page` (integer, default: 1) — Page number
- `per_page` (integer, default: 20, max: 100) — Results per page
- `status` (string, optional) — Filter by status: `pending`, `running`, `paused`, `completed`, `failed`
- `phase` (string, optional) — Filter by phase: `bootstrap`, `discovery`, `architecture`, etc.

**Response:**
```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "my-saas-app",
      "git_url": "git@github.com:myorg/my-saas-app.git",
      "working_path": "/Users/user/projects/my-saas-app",
      "status": "running",
      "phase": "development",
      "active_prd_id": "660e8400-e29b-41d4-a716-446655440001",
      "config": {
        "max_concurrent_agents": 10,
        "quality_gates_enabled": true
      },
      "inserted_at": "2026-03-01T10:00:00Z",
      "updated_at": "2026-03-03T14:23:45Z"
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 5,
    "total_pages": 1
  }
}
```

### Get Project

**GET** `/api/projects/:id`

Returns a single project by ID or git URL.

**Response:** Same as individual project object above.

### Create Project

**POST** `/api/projects`

Creates a new project.

**Request Body:**
```json
{
  "project": {
    "name": "my-new-app",
    "git_url": "git@github.com:myorg/my-new-app.git",
    "working_path": "/Users/user/projects/my-new-app",
    "prd_content": "# My App\n\n## Features\n- User auth\n- Dashboard",
    "config": {
      "max_concurrent_agents": 15
    }
  }
}
```

**Response:** HTTP 201 with created project object.

### Update Project

**PUT/PATCH** `/api/projects/:id`

Updates an existing project.

**Request Body:**
```json
{
  "project": {
    "name": "updated-name",
    "config": {
      "max_concurrent_agents": 20
    }
  }
}
```

**Response:** HTTP 200 with updated project object.

### Delete Project

**DELETE** `/api/projects/:id`

Deletes a project. This terminates all agents, cancels pending tasks, and removes all associated data.

**Response:** HTTP 204 No Content

### Pause Project

**POST** `/api/projects/:id/pause`

Pauses a running project. Agents complete their current tasks and then stop.

**Response:**
```json
{
  "status": "paused",
  "message": "Project paused successfully"
}
```

### Resume Project

**POST** `/api/projects/:id/resume`

Resumes a paused project from its last checkpoint.

**Response:**
```json
{
  "status": "running",
  "message": "Project resumed successfully"
}
```

---

## PRD Management

PRDs (Product Requirements Documents) are scoped to projects. Multiple PRDs can exist per project, but only one is active at a time.

### List PRDs

**GET** `/api/projects/:project_id/prds`

Returns all PRDs for a project.

**Response:**
```json
{
  "data": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "project_id": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Initial Product Requirements",
      "content": "# My SaaS App\n\n## Features...",
      "content_hash": "sha256:abc123...",
      "status": "in_progress",
      "metadata": {
        "author": "user@example.com",
        "version": "1.0"
      },
      "inserted_at": "2026-03-01T10:00:00Z",
      "updated_at": "2026-03-03T14:23:45Z"
    }
  ]
}
```

**PRD Status Values:**
- `draft` — Being edited, not yet approved
- `approved` — Approved, ready to start
- `in_progress` — Currently being executed
- `paused` — Execution paused
- `completed` — All requirements met
- `archived` — Historical record

### Get PRD

**GET** `/api/projects/:project_id/prds/:id`

Returns a single PRD with execution statistics.

**Response:**
```json
{
  "id": "660e8400-e29b-41d4-a716-446655440001",
  "project_id": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Initial Product Requirements",
  "content": "# My SaaS App...",
  "status": "in_progress",
  "stats": {
    "total_tasks": 120,
    "completed_tasks": 45,
    "active_agents": 8,
    "progress_percentage": 37.5
  }
}
```

### Create PRD

**POST** `/api/projects/:project_id/prds`

Creates a new PRD for a project.

**Request Body:**
```json
{
  "prd": {
    "title": "Version 2.0 Requirements",
    "content": "# Version 2.0\n\n## New Features...",
    "metadata": {
      "author": "user@example.com"
    }
  }
}
```

**Response:** HTTP 201 with created PRD object.

### Update PRD

**PUT/PATCH** `/api/projects/:project_id/prds/:id`

Updates an existing PRD. If the PRD is `in_progress`, updating the content triggers re-planning.

**Request Body:**
```json
{
  "prd": {
    "content": "# Updated content..."
  }
}
```

**Response:** HTTP 200 with updated PRD object.

### Delete PRD

**DELETE** `/api/projects/:project_id/prds/:id`

Deletes a PRD. Active PRDs cannot be deleted.

**Response:** HTTP 204 No Content

---

## Task Management

Tasks are work items created during PRD execution. They are hierarchical (parent/child relationships) and tracked by priority.

### List Tasks

**GET** `/api/projects/:project_id/tasks`

Returns all tasks for a project.

**Query Parameters:**
- `prd_id` (UUID, optional) — Filter by PRD
- `status` (string, optional) — Filter by status: `pending`, `running`, `completed`, `failed`, `dead_letter`
- `priority` (integer, optional) — Filter by priority (1 = highest)
- `page`, `per_page` — Pagination

**Response:**
```json
{
  "data": [
    {
      "id": "770e8400-e29b-41d4-a716-446655440002",
      "project_id": "550e8400-e29b-41d4-a716-446655440000",
      "parent_task_id": null,
      "type": "implement_feature",
      "priority": 5,
      "status": "completed",
      "payload": {
        "prd_id": "660e8400-e29b-41d4-a716-446655440001",
        "feature": "user_authentication",
        "files": ["lib/auth.ex", "test/auth_test.exs"]
      },
      "result": {
        "success": true,
        "tests_passed": 15
      },
      "error": null,
      "agent_id": "eng-backend-001",
      "attempts": 1,
      "tokens_used": 4500,
      "duration_ms": 12340,
      "inserted_at": "2026-03-03T12:00:00Z",
      "updated_at": "2026-03-03T12:00:12Z"
    }
  ],
  "meta": {
    "page": 1,
    "per_page": 20,
    "total": 120
  }
}
```

### Get Task

**GET** `/api/projects/:project_id/tasks/:id`

Returns a single task with full details including subtasks.

**Response:** Same as individual task object above, plus:
```json
{
  "subtasks": [
    {
      "id": "880e8400-e29b-41d4-a716-446655440003",
      "type": "write_tests",
      "status": "completed"
    }
  ]
}
```

### Retry Task

**POST** `/api/projects/:project_id/tasks/:id/retry`

Retries a failed task. Resets attempts counter and re-enqueues.

**Response:**
```json
{
  "message": "Task retry scheduled",
  "task_id": "770e8400-e29b-41d4-a716-446655440002",
  "status": "pending"
}
```

---

## Agent Runs

Agent runs track the execution history of agent workers across the RARV cycle.

### List Agent Runs

**GET** `/api/projects/:project_id/agents`

Returns all agent runs for a project.

**Query Parameters:**
- `agent_type` (string, optional) — Filter by type: `eng-frontend`, `eng-backend`, etc.
- `status` (string, optional) — Filter by status: `idle`, `reason`, `act`, `reflect`, `verify`, `failed`, `completed`
- `page`, `per_page` — Pagination

**Response:**
```json
{
  "data": [
    {
      "id": "990e8400-e29b-41d4-a716-446655440004",
      "project_id": "550e8400-e29b-41d4-a716-446655440000",
      "agent_type": "eng-backend",
      "agent_id": "eng-backend-001",
      "status": "completed",
      "node": "node1@localhost",
      "pid": "#PID<0.1234.0>",
      "metrics": {
        "rarv_cycles": 5,
        "tasks_completed": 3,
        "tokens_used": 15000,
        "duration_ms": 45000
      },
      "started_at": "2026-03-03T12:00:00Z",
      "completed_at": "2026-03-03T12:00:45Z"
    }
  ]
}
```

### Get Agent Run

**GET** `/api/projects/:project_id/agents/:id`

Returns a single agent run with detailed execution trace.

**Response:** Same as individual agent run object above, plus:
```json
{
  "trace": [
    {
      "timestamp": "2026-03-03T12:00:05Z",
      "state": "reason",
      "event": "Task identified: implement_auth"
    },
    {
      "timestamp": "2026-03-03T12:00:15Z",
      "state": "act",
      "event": "Executing implementation"
    }
  ]
}
```

---

## Webhooks

Webhooks provide event notifications for project lifecycle events.

### List Webhooks

**GET** `/api/webhooks`

Returns all configured webhooks.

**Response:**
```json
{
  "data": [
    {
      "id": "aa0e8400-e29b-41d4-a716-446655440005",
      "url": "https://api.example.com/samgita/events",
      "events": ["phase_changed", "task_completed", "agent_failed"],
      "secret": "whsec_...",
      "active": true,
      "inserted_at": "2026-03-01T10:00:00Z"
    }
  ]
}
```

**Event Types:**
- `project_created`, `project_started`, `project_paused`, `project_completed`, `project_failed`
- `phase_changed`
- `agent_spawned`, `agent_state_changed`, `agent_failed`, `agent_completed`
- `task_created`, `task_started`, `task_completed`, `task_failed`
- `prd_created`, `prd_approved`, `prd_completed`

### Create Webhook

**POST** `/api/webhooks`

Creates a new webhook subscription.

**Request Body:**
```json
{
  "webhook": {
    "url": "https://api.example.com/samgita/events",
    "events": ["phase_changed", "task_completed"],
    "secret": "your_secret_key"
  }
}
```

**Response:** HTTP 201 with created webhook object.

### Delete Webhook

**DELETE** `/api/webhooks/:id`

Deletes a webhook subscription.

**Response:** HTTP 204 No Content

---

## Notifications

Notifications track system messages and alerts.

### List Notifications

**GET** `/api/notifications`

Returns notifications with filtering.

**Query Parameters:**
- `status` (string, optional) — Filter by: `unread`, `read`, `archived`
- `severity` (string, optional) — Filter by: `info`, `warning`, `error`, `critical`
- `page`, `per_page` — Pagination

**Response:**
```json
{
  "data": [
    {
      "id": "bb0e8400-e29b-41d4-a716-446655440006",
      "title": "Task Failed",
      "message": "Task 'implement_auth' failed after 5 attempts",
      "severity": "error",
      "status": "unread",
      "metadata": {
        "project_id": "550e8400-e29b-41d4-a716-446655440000",
        "task_id": "770e8400-e29b-41d4-a716-446655440002"
      },
      "inserted_at": "2026-03-03T14:23:45Z"
    }
  ]
}
```

### Get Notification

**GET** `/api/notifications/:id`

Returns a single notification. Marks as read automatically.

**Response:** Same as individual notification object above.

### Create Notification

**POST** `/api/notifications`

Creates a custom notification (for integrations).

**Request Body:**
```json
{
  "notification": {
    "title": "Custom Alert",
    "message": "Something happened",
    "severity": "warning",
    "metadata": {
      "source": "external_system"
    }
  }
}
```

**Response:** HTTP 201 with created notification object.

### Update Notification

**PATCH** `/api/notifications/:id`

Updates notification status.

**Request Body:**
```json
{
  "notification": {
    "status": "read"
  }
}
```

**Response:** HTTP 200 with updated notification object.

### Delete Notification

**DELETE** `/api/notifications/:id`

Deletes a notification.

**Response:** HTTP 204 No Content

---

## Feature Flags

Feature flags enable/disable system capabilities at runtime.

### List Features

**GET** `/api/features`

Returns all feature flags.

**Response:**
```json
{
  "data": [
    {
      "id": "cc0e8400-e29b-41d4-a716-446655440007",
      "key": "blind_review",
      "name": "Blind Review System",
      "description": "Enable parallel blind review by 3 independent agents",
      "enabled": true,
      "archived": false,
      "metadata": {
        "default_reviewers": 3
      },
      "inserted_at": "2026-03-01T10:00:00Z"
    }
  ]
}
```

### Get Feature

**GET** `/api/features/:id`

Returns a single feature flag.

**Response:** Same as individual feature object above.

### Create Feature

**POST** `/api/features`

Creates a new feature flag.

**Request Body:**
```json
{
  "feature": {
    "key": "anti_sycophancy",
    "name": "Anti-Sycophancy Gate",
    "description": "Devil's advocate review on unanimous approval",
    "enabled": false,
    "metadata": {
      "trigger_threshold": "unanimous"
    }
  }
}
```

**Response:** HTTP 201 with created feature object.

### Update Feature

**PATCH** `/api/features/:id`

Updates a feature flag.

**Request Body:**
```json
{
  "feature": {
    "description": "Updated description",
    "metadata": {
      "new_setting": true
    }
  }
}
```

**Response:** HTTP 200 with updated feature object.

### Enable Feature

**POST** `/api/features/:id/enable`

Enables a feature flag.

**Response:**
```json
{
  "enabled": true,
  "message": "Feature enabled successfully"
}
```

### Disable Feature

**POST** `/api/features/:id/disable`

Disables a feature flag.

**Response:**
```json
{
  "enabled": false,
  "message": "Feature disabled successfully"
}
```

### Archive Feature

**POST** `/api/features/:id/archive`

Archives a feature flag (soft delete).

**Response:**
```json
{
  "archived": true,
  "message": "Feature archived successfully"
}
```

### Delete Feature

**DELETE** `/api/features/:id`

Permanently deletes a feature flag.

**Response:** HTTP 204 No Content

---

## Error Responses

All error responses follow this format:

```json
{
  "errors": {
    "field_name": ["error message 1", "error message 2"]
  }
}
```

**Common HTTP Status Codes:**
- `400 Bad Request` — Invalid parameters or request body
- `401 Unauthorized` — Missing or invalid API key
- `404 Not Found` — Resource does not exist
- `422 Unprocessable Entity` — Validation errors
- `429 Too Many Requests` — Rate limit exceeded
- `500 Internal Server Error` — Server error

**Example Error Response:**
```json
{
  "errors": {
    "git_url": ["has already been taken"],
    "name": ["can't be blank"]
  }
}
```

**Rate Limit Headers:**
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1709481825
```

---

## Webhook Payloads

Webhooks are delivered via HTTP POST with HMAC-SHA256 signature verification.

**Headers:**
```
Content-Type: application/json
X-Samgita-Event: phase_changed
X-Samgita-Signature: sha256=abc123...
X-Samgita-Delivery: uuid-v4
```

**Signature Verification (Python):**
```python
import hmac
import hashlib

def verify_signature(payload, signature, secret):
    expected = "sha256=" + hmac.new(
        secret.encode(),
        payload.encode(),
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, signature)
```

**Example Payload (phase_changed):**
```json
{
  "event": "phase_changed",
  "timestamp": "2026-03-03T14:23:45Z",
  "data": {
    "project_id": "550e8400-e29b-41d4-a716-446655440000",
    "project_name": "my-saas-app",
    "old_phase": "architecture",
    "new_phase": "development"
  }
}
```

**Example Payload (task_completed):**
```json
{
  "event": "task_completed",
  "timestamp": "2026-03-03T14:23:45Z",
  "data": {
    "task_id": "770e8400-e29b-41d4-a716-446655440002",
    "project_id": "550e8400-e29b-41d4-a716-446655440000",
    "type": "implement_feature",
    "agent_id": "eng-backend-001",
    "duration_ms": 12340,
    "success": true
  }
}
```

---

## Client Libraries

### cURL Examples

**Create Project:**
```bash
curl -X POST http://localhost:3110/api/projects \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your_api_key" \
  -d '{
    "project": {
      "name": "my-app",
      "git_url": "git@github.com:user/my-app.git"
    }
  }'
```

**Get Tasks:**
```bash
curl "http://localhost:3110/api/projects/$PROJECT_ID/tasks?status=completed" \
  -H "X-API-Key: your_api_key"
```

**Pause Project:**
```bash
curl -X POST "http://localhost:3110/api/projects/$PROJECT_ID/pause" \
  -H "X-API-Key: your_api_key"
```

### Python Example

```python
import requests

class SamgitaClient:
    def __init__(self, base_url="http://localhost:3110", api_key=None):
        self.base_url = base_url
        self.headers = {"X-API-Key": api_key} if api_key else {}

    def create_project(self, name, git_url, prd_content):
        response = requests.post(
            f"{self.base_url}/api/projects",
            json={"project": {
                "name": name,
                "git_url": git_url,
                "prd_content": prd_content
            }},
            headers=self.headers
        )
        return response.json()

    def get_tasks(self, project_id, status=None):
        params = {"status": status} if status else {}
        response = requests.get(
            f"{self.base_url}/api/projects/{project_id}/tasks",
            params=params,
            headers=self.headers
        )
        return response.json()

# Usage
client = SamgitaClient(api_key="your_key")
project = client.create_project("my-app", "git@github.com:user/my-app.git", "# PRD...")
tasks = client.get_tasks(project["id"], status="completed")
```

---

## Best Practices

1. **Use webhooks for event notifications** instead of polling the API
2. **Cache project/PRD data** — these change infrequently
3. **Verify webhook signatures** to prevent spoofing
4. **Implement exponential backoff** for rate limit errors (429)
5. **Use pagination** for large result sets
6. **Filter tasks by prd_id** to scope queries to specific PRD executions
7. **Monitor rate limit headers** to avoid hitting limits
8. **Use feature flags** to enable/disable capabilities without code changes

---

## Rate Limiting

Samgita implements a token bucket rate limiter with the following defaults:

- **Limit:** 100 requests per IP
- **Window:** 60 seconds
- **Burst:** Allows brief bursts up to limit

**Configuration:**
```elixir
# config/runtime.exs
config :samgita_web, SamgitaWeb.Plugs.RateLimit,
  limit: 100,
  window_ms: 60_000
```

**Rate Limit Response:**
```json
{
  "error": "Rate limit exceeded. Try again in 45 seconds."
}
```

---

## Versioning

The API uses URL versioning. Future versions will be available at `/api/v2`, etc.

Current version: **v1** (implicit, no version prefix required)

---

**Last Updated:** 2026-03-03
**API Version:** 1.0.0
