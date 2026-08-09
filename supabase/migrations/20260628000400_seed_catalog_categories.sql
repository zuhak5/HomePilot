insert into public.catalog_categories (
  id,
  name,
  health_group,
  icon_name
)
values
  ('category_safety', 'Safety', 'safety', 'shield'),
  ('category_pets', 'Pets', 'pets', 'pets'),
  ('category_appliances', 'Appliances', 'appliances', 'kitchen'),
  ('category_plants', 'Plants', 'plants', 'yard'),
  ('category_cleaning', 'Cleaning', 'cleaning', 'cleaning_services'),
  ('category_general', 'General', 'other', 'home')
on conflict (id) do update set
  name = excluded.name,
  health_group = excluded.health_group,
  icon_name = excluded.icon_name,
  updated_at = now();
