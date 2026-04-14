create table if not exists public.exercise_goals (
    id                     uuid        primary key,
    user_id                uuid        not null references auth.users(id) on delete cascade,
    exercise_id            uuid        not null,
    target_weight_increase real        not null,
    baseline_weight        real        not null,
    deadline               timestamptz not null,
    is_completed           boolean     not null default false,
    completed_at           timestamptz,
    created_at             timestamptz not null default now()
);

alter table public.exercise_goals enable row level security;

create policy "Users can manage their own goals"
    on public.exercise_goals
    for all
    using  (auth.uid() = user_id)
    with check (auth.uid() = user_id);
