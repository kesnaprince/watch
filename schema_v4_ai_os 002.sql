-- =====================================================
-- WATCHTOWER AI OS v4 — Agents, Shadow Auditor, Integrations
-- Run AFTER schema.sql (or as additive migration)
-- =====================================================

-- Agent runs / recommendations
create table if not exists agent_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  agent_key text not null,
  title text not null,
  summary text,
  recommendation text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','executed')),
  priority text default 'medium',
  created_at timestamptz not null default now(),
  acted_by uuid references auth.users(id)
);

-- Shadow Auditor scan logs
create table if not exists shadow_audit_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  user_id uuid references auth.users(id),
  destination text,
  original_preview text,
  findings jsonb default '[]'::jsonb,
  action_taken text not null default 'allowed'
    check (action_taken in ('allowed','blocked','masked','needs_approval')),
  created_at timestamptz not null default now()
);

-- Integration connections registry
create table if not exists integrations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  provider text not null,
  display_name text not null,
  status text not null default 'disconnected'
    check (status in ('connected','disconnected','error','pending')),
  scopes text[],
  last_sync_at timestamptz,
  meta jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Company knowledge / AI memory snippets
create table if not exists knowledge_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  title text not null,
  body text,
  source text,
  tags text[],
  created_at timestamptz not null default now()
);

alter table agent_runs enable row level security;
alter table shadow_audit_logs enable row level security;
alter table integrations enable row level security;
alter table knowledge_items enable row level security;

drop policy if exists "company agent_runs" on agent_runs;
create policy "company agent_runs" on agent_runs for all using (company_id = my_company_id()) with check (company_id = my_company_id());

drop policy if exists "company shadow_audit" on shadow_audit_logs;
create policy "company shadow_audit" on shadow_audit_logs for all using (company_id = my_company_id()) with check (company_id = my_company_id());

drop policy if exists "company integrations" on integrations;
create policy "company integrations" on integrations for all using (company_id = my_company_id()) with check (company_id = my_company_id());

drop policy if exists "company knowledge" on knowledge_items;
create policy "company knowledge" on knowledge_items for select using (company_id = my_company_id());
drop policy if exists "ceo write knowledge" on knowledge_items;
create policy "ceo write knowledge" on knowledge_items for all using (company_id = my_company_id() and my_role() = 'ceo') with check (company_id = my_company_id());

-- Seed integrations catalog for Acme
do $$
declare cid uuid;
begin
  select id into cid from companies where name = 'Acme Corp' order by created_at desc limit 1;
  if cid is null then return; end if;

  insert into integrations (company_id, provider, display_name, status)
  select cid, p.provider, p.display_name, p.status
  from (values
    ('keka', 'Keka HR', 'disconnected'),
    ('zoho_crm', 'Zoho CRM', 'disconnected'),
    ('zoho_marketing', 'Zoho Marketing', 'disconnected'),
    ('salesforce', 'Salesforce', 'disconnected'),
    ('hubspot', 'HubSpot', 'disconnected'),
    ('google_workspace', 'Google Workspace', 'disconnected'),
    ('microsoft_365', 'Microsoft 365', 'disconnected'),
    ('slack', 'Slack', 'disconnected'),
    ('teams', 'Microsoft Teams', 'disconnected'),
    ('jira', 'Jira', 'disconnected'),
    ('quickbooks', 'QuickBooks', 'disconnected'),
    ('stripe', 'Stripe', 'disconnected')
  ) as p(provider, display_name, status)
  where not exists (
    select 1 from integrations where company_id = cid and provider = p.provider
  );

  insert into knowledge_items (company_id, title, body, source, tags)
  select cid, k.title, k.body, k.source, k.tags
  from (values
    ('Q3 North Star', 'Reach $4.2M ARR, 98% NRR, burn under $180k/mo.', 'Executive', array['okr','strategy']),
    ('AI usage policy', 'No PII or credentials in external LLM prompts. Shadow Auditor enforces.', 'Compliance', array['security','ai']),
    ('DACH expansion', 'Approved geographic expansion into DACH markets.', 'Executive', array['strategy'])
  ) as k(title, body, source, tags)
  where not exists (select 1 from knowledge_items where company_id = cid and title = k.title);
end $$;

UPDATE public.profiles
SET
    company_id = '54ab08fd-976d-4696-a829-746d842464e1',
    role = 'ceo'
WHERE id = '9e44209f-4545-4dfb-81d0-f120d02fd59f';