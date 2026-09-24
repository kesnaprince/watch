-- =====================================================
-- WATCHTOWER — PostgreSQL schema for Supabase
-- Run this in: Supabase Dashboard → SQL Editor → New query
-- =====================================================

create extension if not exists "pgcrypto";

-- ---------- COMPANIES ----------
create table if not exists companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  founder_score int default 70,
  pipeline text default '$0',
  headcount int default 0,
  open_requisitions int default 0,
  approvals int default 0,
  ai_risk_score int default 0,
  created_at timestamptz not null default now()
);

-- ---------- PROFILES (1:1 with auth.users) ----------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid references companies(id) on delete set null,
  full_name text,
  role text not null default 'employee'
    check (role in ('ceo','manager','employee')),
  department text,
  created_at timestamptz not null default now()
);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    'employee'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------- RLS HELPERS ----------
create or replace function my_company_id()
returns uuid language sql security definer set search_path = public stable as $$
  select company_id from profiles where id = auth.uid();
$$;

create or replace function my_department()
returns text language sql security definer set search_path = public stable as $$
  select department from profiles where id = auth.uid();
$$;

create or replace function my_role()
returns text language sql security definer set search_path = public stable as $$
  select role from profiles where id = auth.uid();
$$;

-- ---------- DASHBOARD TABLES ----------
create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  name text not null,
  score int not null default 70,
  sort_order int default 0,
  created_at timestamptz not null default now()
);

create table if not exists alerts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  level text not null default 'MED',
  title text not null,
  description text,
  created_at timestamptz not null default now()
);

create table if not exists actions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  title text not null,
  description text,
  sort_order int default 0,
  created_at timestamptz not null default now()
);

create table if not exists activities (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  actor_name text,
  action_text text,
  type text default 'blue',
  created_at timestamptz not null default now()
);

create table if not exists wins (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  text text not null,
  created_at timestamptz not null default now()
);

create table if not exists risks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  name text not null,
  level text,
  value int default 0,
  class_name text default 'low',
  sort_order int default 0,
  created_at timestamptz not null default now()
);

create table if not exists ai_monitoring (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  title text not null,
  number text,
  description text,
  status text default 'OK',
  sort_order int default 0,
  created_at timestamptz not null default now()
);

-- ---------- APPROVALS ----------
create table if not exists approvals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  title text not null,
  amount text,
  amount_value numeric,
  category text default 'General',
  description text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  requested_by text,
  requested_by_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- ---------- PROCUREMENT ----------
create table if not exists procurement_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  vendor text not null,
  item text not null,
  amount numeric not null default 0,
  amount_value numeric,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected')),
  requested_by text,
  requested_by_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);

-- ---------- EMPLOYEES ----------
create table if not exists employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  name text not null,
  title text,
  department text,
  email text,
  status text not null default 'active'
    check (status in ('active','on_leave','offboarded')),
  risk text not null default 'low'
    check (risk in ('low','medium','high')),
  created_at timestamptz not null default now()
);

-- ---------- FINANCE ----------
create table if not exists transactions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  description text not null,
  amount numeric not null,
  type text not null check (type in ('income','expense')),
  occurred_on date default current_date,
  created_at timestamptz not null default now()
);

-- ---------- SALES ----------
create table if not exists deals (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  name text not null,
  value numeric not null default 0,
  stage text not null default 'prospecting'
    check (stage in ('prospecting','negotiation','closed_won','closed_lost')),
  owner text,
  close_date date,
  created_at timestamptz not null default now()
);

-- ---------- NOTIFICATIONS ----------
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  title text not null,
  message text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------- AUTOMATION RULES ----------
create table if not exists automation_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  name text not null,
  rule_type text not null
    check (rule_type in (
      'auto_approve_approvals',
      'auto_approve_procurement',
      'auto_notify_high_risk'
    )),
  threshold numeric,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------- ISSUES ----------
create table if not exists issues (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references companies(id) on delete cascade,
  title text not null,
  description text,
  department text,
  severity text not null default 'medium'
    check (severity in ('low','medium','high','critical')),
  status text not null default 'open'
    check (status in ('open','in_progress','resolved')),
  raised_by text,
  raised_by_id uuid references auth.users(id),
  resolved_by text,
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================
alter table companies enable row level security;
alter table profiles enable row level security;
alter table departments enable row level security;
alter table alerts enable row level security;
alter table actions enable row level security;
alter table activities enable row level security;
alter table wins enable row level security;
alter table risks enable row level security;
alter table ai_monitoring enable row level security;
alter table approvals enable row level security;
alter table procurement_requests enable row level security;
alter table employees enable row level security;
alter table transactions enable row level security;
alter table deals enable row level security;
alter table notifications enable row level security;
alter table automation_rules enable row level security;
alter table issues enable row level security;

-- Profiles
drop policy if exists "users read own profile" on profiles;
create policy "users read own profile" on profiles for select using (id = auth.uid());
drop policy if exists "users update own profile" on profiles;
create policy "users update own profile" on profiles for update using (id = auth.uid());

-- Company-scoped reads
drop policy if exists "company read departments" on departments;
create policy "company read departments" on departments for select using (company_id = my_company_id());
drop policy if exists "company read alerts" on alerts;
create policy "company read alerts" on alerts for select using (company_id = my_company_id());
drop policy if exists "company read actions" on actions;
create policy "company read actions" on actions for select using (company_id = my_company_id());
drop policy if exists "company read activities" on activities;
create policy "company read activities" on activities for select using (company_id = my_company_id());
drop policy if exists "company read wins" on wins;
create policy "company read wins" on wins for select using (company_id = my_company_id());
drop policy if exists "company read risks" on risks;
create policy "company read risks" on risks for select using (company_id = my_company_id());
drop policy if exists "company read ai_monitoring" on ai_monitoring;
create policy "company read ai_monitoring" on ai_monitoring for select using (company_id = my_company_id());

-- Approvals
drop policy if exists "scoped read approvals" on approvals;
create policy "scoped read approvals" on approvals for select using (
  company_id = my_company_id() and (my_role() = 'ceo' or requested_by_id = auth.uid())
);
drop policy if exists "insert own approvals" on approvals;
create policy "insert own approvals" on approvals for insert with check (
  company_id = my_company_id() and requested_by_id = auth.uid()
);
drop policy if exists "ceo update approvals" on approvals;
create policy "ceo update approvals" on approvals for update using (
  company_id = my_company_id() and my_role() = 'ceo'
);

-- Procurement
drop policy if exists "scoped read procurement" on procurement_requests;
create policy "scoped read procurement" on procurement_requests for select using (
  company_id = my_company_id() and (my_role() = 'ceo' or requested_by_id = auth.uid())
);
drop policy if exists "insert own procurement" on procurement_requests;
create policy "insert own procurement" on procurement_requests for insert with check (
  company_id = my_company_id() and requested_by_id = auth.uid()
);
drop policy if exists "ceo update procurement" on procurement_requests;
create policy "ceo update procurement" on procurement_requests for update using (
  company_id = my_company_id() and my_role() = 'ceo'
);

-- Employees
drop policy if exists "company read employees" on employees;
create policy "company read employees" on employees for select using (company_id = my_company_id());
drop policy if exists "ceo write all employees" on employees;
create policy "ceo write all employees" on employees for all using (
  company_id = my_company_id() and my_role() = 'ceo'
) with check (company_id = my_company_id());
drop policy if exists "manager write own department employees" on employees;
create policy "manager write own department employees" on employees for all using (
  company_id = my_company_id() and my_role() = 'manager' and department = my_department()
) with check (company_id = my_company_id() and department = my_department());

-- Finance (hide from employees)
drop policy if exists "ceo_manager read transactions" on transactions;
create policy "ceo_manager read transactions" on transactions for select using (
  company_id = my_company_id() and my_role() in ('ceo','manager')
);
drop policy if exists "ceo write transactions" on transactions;
create policy "ceo write transactions" on transactions for all using (
  company_id = my_company_id() and my_role() = 'ceo'
) with check (company_id = my_company_id());

-- Sales
drop policy if exists "ceo_manager read deals" on deals;
create policy "ceo_manager read deals" on deals for select using (
  company_id = my_company_id() and my_role() in ('ceo','manager')
);
drop policy if exists "ceo write deals" on deals;
create policy "ceo write deals" on deals for all using (
  company_id = my_company_id() and my_role() = 'ceo'
) with check (company_id = my_company_id());

-- Notifications
drop policy if exists "company read notifications" on notifications;
create policy "company read notifications" on notifications for select using (company_id = my_company_id());
drop policy if exists "company update notifications" on notifications;
create policy "company update notifications" on notifications for update using (company_id = my_company_id());

-- Automation
drop policy if exists "ceo_manager read automation_rules" on automation_rules;
create policy "ceo_manager read automation_rules" on automation_rules for select using (
  company_id = my_company_id() and my_role() in ('ceo','manager')
);
drop policy if exists "ceo write automation_rules" on automation_rules;
create policy "ceo write automation_rules" on automation_rules for all using (
  company_id = my_company_id() and my_role() = 'ceo'
) with check (company_id = my_company_id());

-- Issues
drop policy if exists "scoped read issues" on issues;
create policy "scoped read issues" on issues for select using (
  company_id = my_company_id() and (
    my_role() = 'ceo' or raised_by_id = auth.uid()
    or (my_role() = 'manager' and department = my_department())
  )
);
drop policy if exists "insert own issues" on issues;
create policy "insert own issues" on issues for insert with check (
  company_id = my_company_id() and raised_by_id = auth.uid()
);
drop policy if exists "managers resolve issues" on issues;
create policy "managers resolve issues" on issues for update using (
  company_id = my_company_id() and (
    my_role() = 'ceo' or (my_role() = 'manager' and department = my_department())
  )
);

-- Companies: members can read own company
drop policy if exists "members read company" on companies;
create policy "members read company" on companies for select using (id = my_company_id());

-- =====================================================
-- AUTOMATION TRIGGERS
-- =====================================================
create or replace function trg_auto_approve_approval()
returns trigger language plpgsql security definer set search_path = public as $$
declare matched_rule automation_rules%rowtype;
begin
  select * into matched_rule from automation_rules
  where company_id = new.company_id and rule_type = 'auto_approve_approvals'
    and enabled = true and new.amount_value is not null and new.amount_value <= threshold
  order by threshold asc limit 1;
  if found then new.status := 'approved'; end if;
  return new;
end; $$;

drop trigger if exists before_approval_insert on approvals;
create trigger before_approval_insert before insert on approvals
  for each row execute procedure trg_auto_approve_approval();

create or replace function trg_auto_approve_procurement()
returns trigger language plpgsql security definer set search_path = public as $$
declare matched_rule automation_rules%rowtype;
begin
  select * into matched_rule from automation_rules
  where company_id = new.company_id and rule_type = 'auto_approve_procurement'
    and enabled = true and new.amount_value is not null and new.amount_value <= threshold
  order by threshold asc limit 1;
  if found then new.status := 'approved'; end if;
  return new;
end; $$;

drop trigger if exists before_procurement_insert on procurement_requests;
create trigger before_procurement_insert before insert on procurement_requests
  for each row execute procedure trg_auto_approve_procurement();

create or replace function trg_auto_notify_high_risk()
returns trigger language plpgsql security definer set search_path = public as $$
declare matched_rule automation_rules%rowtype;
begin
  if new.risk = 'high' and (tg_op = 'INSERT' or old.risk is distinct from new.risk) then
    select * into matched_rule from automation_rules
    where company_id = new.company_id and rule_type = 'auto_notify_high_risk' and enabled = true limit 1;
    if found then
      insert into notifications (company_id, title, message)
      values (new.company_id, 'High risk employee flagged',
        new.name || ' has been flagged as high risk and may need attention.');
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists after_employee_risk_change on employees;
create trigger after_employee_risk_change after insert or update on employees
  for each row execute procedure trg_auto_notify_high_risk();

create or replace function trg_issues_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

drop trigger if exists before_issues_update on issues;
create trigger before_issues_update before update on issues
  for each row execute procedure trg_issues_updated_at();

-- =====================================================
-- SEED: Acme Corp + sample data
-- =====================================================
do $$
declare cid uuid;
begin
  select id into cid from companies where name = 'Acme Corp' order by created_at desc limit 1;
  if cid is null then
    insert into companies (name, founder_score, pipeline, headcount, open_requisitions, approvals, ai_risk_score)
    values ('Acme Corp', 71, '$2.4M', 48, 3, 5, 34)
    returning id into cid;
  end if;

  insert into departments (company_id, name, score, sort_order)
  select cid, d.name, d.score, d.sort_order from (values
    ('Engineering', 78, 1), ('Sales', 71, 2), ('Marketing', 68, 3),
    ('Customer Success', 82, 4), ('Finance', 74, 5), ('Product', 76, 6)
  ) as d(name, score, sort_order)
  where not exists (select 1 from departments where company_id = cid and name = d.name);

  insert into automation_rules (company_id, name, rule_type, threshold, enabled)
  select cid, r.name, r.rule_type, r.threshold, true from (values
    ('Auto-approve small expense requests', 'auto_approve_approvals', 500::numeric),
    ('Auto-approve small procurement orders', 'auto_approve_procurement', 1000::numeric),
    ('Notify on high-risk employees', 'auto_notify_high_risk', null::numeric)
  ) as r(name, rule_type, threshold)
  where not exists (select 1 from automation_rules where company_id = cid and name = r.name);

  insert into employees (company_id, name, title, department, email, status, risk)
  select cid, e.name, e.title, e.department, e.email, 'active', e.risk from (values
    ('Alex Chen', 'Senior Front-end Engineer', 'Engineering', 'alex@acme.com', 'low'),
    ('Jordan Lee', 'Back-end Engineer', 'Engineering', 'jordan@acme.com', 'low'),
    ('Sam Rivera', 'UI/UX Designer', 'Design', 'sam@acme.com', 'low'),
    ('Taylor Kim', 'Manual QA', 'Engineering', 'taylor@acme.com', 'medium'),
    ('Casey Brooks', 'Automation QA', 'Engineering', 'casey@acme.com', 'low'),
    ('Morgan Blake', 'Product Manager', 'Product', 'morgan@acme.com', 'low'),
    ('Riley Quinn', 'Account Executive', 'Sales', 'riley@acme.com', 'low'),
    ('Jamie Ortiz', 'Legal Counsel', 'Legal', 'jamie@acme.com', 'low')
  ) as e(name, title, department, email, risk)
  where not exists (select 1 from employees where company_id = cid and email = e.email);

  insert into alerts (company_id, level, title, description)
  select cid, a.level, a.title, a.description from (values
    ('CRIT', 'Phishing campaign detected', '3 users reported. SOC investigating.'),
    ('HIGH', 'Enterprise deal at risk', 'Northwind MSA stuck on liability language.'),
    ('MED', 'Sprint capacity tight', 'Engineering velocity below target this sprint.')
  ) as a(level, title, description)
  where not exists (select 1 from alerts where company_id = cid and title = a.title);

  insert into actions (company_id, title, description, sort_order)
  select cid, a.title, a.description, a.sort_order from (values
    ('Review Northwind MSA', 'Legal + Sales need CEO decision on liability cap.', 1),
    ('Approve marketing budget top-up', 'Launch campaign needs +$12k this week.', 2),
    ('Close 2 P0 bugs before release', 'Engineering has patches ready for review.', 3)
  ) as a(title, description, sort_order)
  where not exists (select 1 from actions where company_id = cid and title = a.title);

  insert into activities (company_id, actor_name, action_text, type)
  select cid, a.actor_name, a.action_text, a.type from (values
    ('Priya S.', 'closed a $48k deal', 'green'),
    ('Marcus T.', 'flagged high-risk employee', 'yellow'),
    ('Aisha K.', 'submitted procurement request', 'blue'),
    ('System', 'auto-approved expense under $500', 'green')
  ) as a(actor_name, action_text, type)
  where not exists (select 1 from activities where company_id = cid and action_text = a.action_text);

  insert into wins (company_id, text)
  select cid, w.text from (values
    ('Closed Contoso expansion — +$62k ARR'),
    ('SOC2 evidence pack 88% complete'),
    ('WatchTower 3.0 waitlist crossed 2,100')
  ) as w(text)
  where not exists (select 1 from wins where company_id = cid and text = w.text);

  insert into risks (company_id, name, level, value, class_name, sort_order)
  select cid, r.name, r.level, r.value, r.class_name, r.sort_order from (values
    ('Churn risk (Contoso)', 'High', 72, 'high', 1),
    ('Security posture', 'Medium', 45, 'high', 2),
    ('Burn runway', 'Low', 22, 'low', 3)
  ) as r(name, level, value, class_name, sort_order)
  where not exists (select 1 from risks where company_id = cid and name = r.name);

  insert into ai_monitoring (company_id, title, number, description, status, sort_order)
  select cid, a.title, a.number, a.description, a.status, a.sort_order from (values
    ('Shadow AI tools', '7', 'Unapproved tools detected in browser traffic.', 'REVIEW', 1),
    ('Model usage (24h)', '14.2k', 'Calls across approved models.', 'OK', 2),
    ('Policy violations', '2', 'Potential PII in prompt logs — quarantined.', 'REVIEW', 3)
  ) as a(title, number, description, status, sort_order)
  where not exists (select 1 from ai_monitoring where company_id = cid and title = a.title);
end $$;

-- =====================================================
-- AFTER SIGNUP: link user to Acme + set role
-- Replace email and role as needed.
-- =====================================================
-- update profiles
-- set company_id = (select id from companies where name = 'Acme Corp' limit 1),
--     role = 'ceo',
--     full_name = 'Your Name'
-- where id = (select id from auth.users where email = 'you@company.com');
--
-- Manager example:
-- update profiles
-- set company_id = (select id from companies where name = 'Acme Corp' limit 1),
--     role = 'manager',
--     department = 'Engineering'
-- where id = (select id from auth.users where email = 'manager@company.com');
