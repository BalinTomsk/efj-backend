
select ',(''' + cast(Family_id as varchar(36)) + ''',''' + [Family_name] + ''',' + cast(fid as varchar(32)) + ')' as line from [dbo].[fish_family]
