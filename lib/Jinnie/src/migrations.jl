module Migrations

using Memoize
using Database
using Jinnie

type Migration 
  migration_hash::AbstractString
  migration_file_name::AbstractString 
  migration_class_name::AbstractString
end

function new(cmd_args, config)
  include(abspath("lib/jinnie/src/file_templates.jl"))
  mfn = migration_file_name(cmd_args, config)
  f = open(mfn, "w")
  ft = FileTemplate()
  write(f, new_database_migration(ft, migration_class_name(cmd_args["db:migration:new"])))
  close(f)

  log("New migration created at $mfn")
end

function migration_hash()
  m = match(r"(\d*)-(\d*)-(\d*)T(\d*):(\d*):(\d*)\.(\d*)", "$(Dates.unix2datetime(time()))")
  return join(m.captures)
end

function migration_file_name(cmd_args, config)
  return config.db_migrations_folder * "/" * migration_hash() * "_" * cmd_args["db:migration:new"] * ".jl"
end

function migration_class_name(underscored_migration_name)
  mapreduce( x -> ucfirst(x), *, split(replace(underscored_migration_name, ".jl", ""), "_") )
end

function last_up(cmd_args, config)
  if ( cmd_args["db:migration:up"] == "true" ) 
    run_migration(last_migration(), config, :up)
  end
end

function last_down(cmd_args, config)
  if ( cmd_args["db:migration:down"] == "true" ) 
    run_migration(last_migration(), config, :down)
  end
end

@memoize function all_migrations()
  migrations = []
  migrations_files = Dict()
  for (f in readdir(Jinnie.config.db_migrations_folder))
    if ( ismatch(r"\d{17}_.*\.jl", f) )
      parts = split(f, "_", limit = 2)
      push!(migrations, parts[1])
      migrations_files[parts[1]] = Migration(parts[1], f, migration_class_name(parts[2]))
    end
  end

  return sort!(migrations), migrations_files
end

@memoize function last_migration()
  migrations, migrations_files = all_migrations()
  return migrations_files[migrations[length(migrations)]]
end

function run_migration(migration, config, direction)
  include(abspath(joinpath(config.db_migrations_folder, migration.migration_file_name)))
  eval(parse("Jinnie.$(string(direction))(Jinnie.$(migration.migration_class_name)())"))
  if ( direction == :up )
    Database.query("INSERT INTO $(Jinnie.config.db_migrations_table_name) VALUES ('$(migration.migration_hash)')")
  else 
    Database.query("""DELETE FROM $(Jinnie.config.db_migrations_table_name) WHERE version = ('$(migration.migration_hash)')""")
  end
end

function upped_migrations()
  result = Database.query("SELECT * FROM $(Jinnie.config.db_migrations_table_name) ORDER BY version DESC")
  return map(x -> x[1], result)
end

function status(parsed_args, config)
  migrations, migrations_files = all_migrations()
  up_migrations = upped_migrations()

  println("")
  
  for m in migrations
    status = ( findfirst(up_migrations, m) > 0 ) ? "up" : "down"
    println( "$m \t|\t $status \t|\t $(migrations_files[m].migration_class_name) \t|\t $(migrations_files[m].migration_file_name)" )
  end

  println("")
end

end