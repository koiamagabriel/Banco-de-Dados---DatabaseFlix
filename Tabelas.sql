-- Extensão para gen_random_uuid()
create extension if not exists pgcrypto;

-- ===========================
-- Tabelas
-- ===========================
create table if not exists public.usuarios (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  email text unique not null,
  senha_hash text not null,
  is_admin boolean not null default false,
  created_at timestamp with time zone default now()
);

create table if not exists public.log_s1 (
  id bigint generated always as identity primary key,
  endpoint text,
  metodo text,
  req_payload jsonb,
  res_payload jsonb,
  status_code int,
  latency_ms int,
  erro text,
  user_id uuid,
  ts timestamp with time zone default now()
);

create table if not exists public.planos (
  codigo text primary key,
  nome text not null,
  descricao text
);

insert into public.planos (codigo, nome, descricao) values
  ('comum','Mensal Comum','Catálogo limitado, sem filtros.')
on conflict (codigo) do nothing;

insert into public.planos (codigo, nome, descricao) values
  ('premium','Mensal Premium','Catálogo selecionado + filtro por gêneros.')
on conflict (codigo) do nothing;

insert into public.planos (codigo, nome, descricao) values
  ('delux','Mensal Delux','Catálogo completo + curtidos + todos filtros.')
on conflict (codigo) do nothing;

create table if not exists public.assinaturas (
  id bigint generated always as identity primary key,
  user_id uuid not null unique references public.usuarios(id) on delete cascade,
  plano_codigo text not null references public.planos(codigo) on update cascade,
  status text not null default 'ativo',
  created_at timestamp with time zone default now()
);

create table if not exists public.pagamentos (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.usuarios(id) on delete cascade,
  plano_codigo text not null references public.planos(codigo) on update cascade,
  nome_impresso text not null,
  last4 text not null,
  validade_mm int not null,
  validade_aa int not null,
  pais text not null,
  endereco1 text not null,
  endereco2 text,
  cidade text not null,
  estado text not null,
  cep text not null,
  created_at timestamp with time zone default now()
);

-- ===========================
-- RLS
-- ===========================
alter table public.usuarios     enable row level security;
alter table public.log_s1       enable row level security;  -- << corrigido (era logs_s1)
alter table public.planos       enable row level security;
alter table public.assinaturas  enable row level security;
alter table public.pagamentos   enable row level security;

do $$
begin
  -- USUÁRIOS
  if not exists (select 1 from pg_policies where tablename='usuarios' and policyname='usuarios_insert_anon') then
    create policy "usuarios_insert_anon" on public.usuarios for insert to anon with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='usuarios' and policyname='usuarios_select_anon') then
    create policy "usuarios_select_anon" on public.usuarios for select to anon using (true);
  end if;

  -- LOGS (apenas insert pelo client)
  if not exists (select 1 from pg_policies where tablename='log_s1' and policyname='logs_insert_anon') then  -- << corrigido tablename
    create policy "logs_insert_anon" on public.log_s1 for insert to anon with check (true);                  -- << corrigido nome da tabela
  end if;

  -- PLANOS (somente leitura)
  if not exists (select 1 from pg_policies where tablename='planos' and policyname='planos_select_anon') then
    create policy "planos_select_anon" on public.planos for select to anon using (true);
  end if;

  -- ASSINATURAS (upsert e select)
  if not exists (select 1 from pg_policies where tablename='assinaturas' and policyname='assinaturas_upsert_anon') then
    create policy "assinaturas_upsert_anon" on public.assinaturas for insert to anon with check (true);
    create policy "assinaturas_update_anon" on public.assinaturas for update to anon using (true) with check (true);
    create policy "assinaturas_select_anon" on public.assinaturas for select to anon using (true);
  end if;

  -- PAGAMENTOS (insert e select mínimo)
  if not exists (select 1 from pg_policies where tablename='pagamentos' and policyname='pagamentos_insert_anon') then
    create policy "pagamentos_insert_anon" on public.pagamentos for insert to anon with check (true);
    create policy "pagamentos_select_anon" on public.pagamentos for select to anon using (true);
  end if;
end$$;
