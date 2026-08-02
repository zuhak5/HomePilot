insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'user-media',
  'user-media',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy user_media_select_own
on storage.objects
for select
to authenticated
using (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy user_media_insert_own
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy user_media_update_own
on storage.objects
for update
to authenticated
using (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy user_media_delete_own
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'user-media'
  and (select auth.uid()) is not null
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
