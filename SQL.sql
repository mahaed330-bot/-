-- متجر الهواتف: الجداول والصلاحيات. نفّذ الملف كاملاً في Supabase > SQL Editor

create table public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'customer' check (role in ('customer','sales','moderator','manager'))
);
create table public.products(
  id bigint generated always as identity primary key,
  name text not null,
  brand text not null,
  price numeric(10,2) not null check (price > 0),
  discount int not null default 0 check (discount between 0 and 60),
  stock boolean not null default true,
  rating numeric(2,1) not null default 0,
  specs jsonb not null default '[]',
  created_at timestamptz default now()
);
create table public.sales(
  id bigint generated always as identity primary key,
  product_id bigint references public.products(id) on delete set null,
  product_name text not null,
  qty int not null check (qty > 0),
  total numeric(12,2) not null,
  sold_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz default now()
);

create function public.my_role() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

-- كل حساب جديد يصبح "customer" تلقائياً
create function public.on_signup() returns trigger
language plpgsql security definer set search_path = public as
$$ begin insert into public.profiles(id, email) values (new.id, new.email); return new; end $$;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.on_signup();

-- المودون يعدّلون التوفر والخصم فقط
create function public.mod_limits() returns trigger language plpgsql as
$$ begin
  if public.my_role() = 'moderator'
     and (new.name, new.brand, new.price, new.specs) is distinct from (old.name, old.brand, old.price, old.specs) then
    raise exception 'المودون يعدّلون التوفر والخصم فقط';
  end if;
  return new;
end $$;
create trigger products_mod before update on public.products
for each row execute function public.mod_limits();

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.sales enable row level security;

-- المنتجات: يقرؤها الجميع، المدير يضيف ويحذف، المودون والمدير يعدّلون
create policy products_read on public.products for select using (true);
create policy products_add on public.products for insert to authenticated with check (public.my_role() = 'manager');
create policy products_del on public.products for delete to authenticated using (public.my_role() = 'manager');
create policy products_upd on public.products for update to authenticated
  using (public.my_role() in ('moderator','manager')) with check (public.my_role() in ('moderator','manager'));

-- المبيعات: للمبيعات والمدير فقط
create policy sales_read on public.sales for select to authenticated using (public.my_role() in ('sales','manager'));
create policy sales_add on public.sales for insert to authenticated
  with check (public.my_role() in ('sales','manager') and sold_by = auth.uid());

-- الحسابات: كل مستخدم يرى حسابه، والمدير يرى الكل ويغيّر الأدوار
create policy profiles_read on public.profiles for select to authenticated using (id = auth.uid() or public.my_role() = 'manager');
create policy profiles_role on public.profiles for update to authenticated
  using (public.my_role() = 'manager') with check (public.my_role() = 'manager');

-- منتجات تجريبية (احذفها أو عدّلها لاحقاً)
insert into public.products(name, brand, price, discount, rating, specs) values
('نوفا X برو','نوفا',899,0,4.8,'[["الشاشة","6.7 بوصة AMOLED"],["التخزين","256 جيجابايت"],["الكاميرا","50 ميجابكسل"],["البطارية","5000 مللي أمبير"]]'),
('نوفا لايت','نوفا',329,20,4.2,'[["الشاشة","6.1 بوصة LCD"],["التخزين","128 جيجابايت"],["الكاميرا","13 ميجابكسل"],["البطارية","4500 مللي أمبير"]]'),
('أوريون ألترا','أوريون',1099,0,4.9,'[["الشاشة","6.9 بوصة 120 هرتز"],["التخزين","512 جيجابايت"],["الكاميرا","108 ميجابكسل"],["البطارية","5200 مللي أمبير"]]'),
('أوريون S','أوريون',649,10,4.4,'[["الشاشة","6.4 بوصة AMOLED"],["التخزين","256 جيجابايت"],["الكاميرا","64 ميجابكسل"],["البطارية","4600 مللي أمبير"]]'),
('فيجا ماكس','فيجا',459,25,4.3,'[["الشاشة","6.8 بوصة 90 هرتز"],["التخزين","128 جيجابايت"],["الكاميرا","50 ميجابكسل"],["البطارية","6000 مللي أمبير"]]'),
('فيجا نوت','فيجا',379,30,4.1,'[["الشاشة","6.6 بوصة LCD"],["التخزين","128 جيجابايت"],["الكاميرا","50 ميجابكسل"],["البطارية","5000 مللي أمبير"]]');
