--Connect to your database as admin and run the following statements to create the schemas

--Create database schema
CREATE SCHEMA boundaries;
CREATE SCHEMA maps;
CREATE SCHEMA parks_and_rec;
CREATE SCHEMA services;

--Upload data into these schemas. Download data here: https://opendata.citywindsor.ca/

--Create roles
CREATE ROLE read_only WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;

CREATE ROLE editor WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;

--Allow each role to connect to the database
GRANT CONNECT ON DATABASE qgis_na_2020_database TO read_only;
GRANT CONNECT ON DATABASE qgis_na_2020_database TO editor;

--Create user and grant membership to read_only role
CREATE USER bob WITH
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	PASSWORD 'test1234';

GRANT read_only TO bob;

--Create user and grant membership to read_only and editor roles 
CREATE USER sarah WITH
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	CONNECTION LIMIT -1
	PASSWORD 'test5678';

GRANT read_only TO sarah;
GRANT editor TO sarah;

--Grant access to each schema for each role
GRANT USAGE ON SCHEMA boundaries TO read_only;
GRANT USAGE ON SCHEMA maps TO read_only;
GRANT USAGE ON SCHEMA parks_and_rec TO read_only;
GRANT USAGE ON SCHEMA services TO read_only;

--Grant read_only permission to view each table
GRANT SELECT ON TABLE boundaries.municipal_election_wards_2018 TO read_only;
GRANT SELECT ON TABLE parks_and_rec.parks TO read_only;
GRANT SELECT ON TABLE services.fire_stations TO read_only;
GRANT SELECT ON TABLE services.hospitals TO read_only;
GRANT SELECT ON TABLE services.police TO read_only;

--Grant editor role permission to edit the parks layer 
GRANT ALL ON SEQUENCE parks_and_rec.parks_id_1_seq TO editor;
GRANT ALL ON TABLE parks_and_rec.parks TO editor;



--Add new columns to the parks table
ALTER TABLE parks_and_rec.parks ADD COLUMN area_sqm numeric;
ALTER TABLE parks_and_rec.parks ADD COLUMN ward varchar;

--Add columns for nearest services and infrastructure 
ALTER TABLE parks_and_rec.parks ADD COLUMN nearest_police_station varchar;
ALTER TABLE parks_and_rec.parks ADD COLUMN nearest_police_station_distance_m numeric;
ALTER TABLE parks_and_rec.parks ADD COLUMN nearest_hospital varchar;
ALTER TABLE parks_and_rec.parks ADD COLUMN nearest_hospital_distance_m numeric;
ALTER TABLE parks_and_rec.parks ADD COLUMN nearest_fire_station varchar;
ALTER TABLE parks_and_rec.parks ADD COLUMN nearest_fire_station_distance_m numeric;

--Now add fields for the metadata fields
ALTER TABLE parks_and_rec.parks ADD COLUMN date_created timestamp with time zone DEFAULT now();
ALTER TABLE parks_and_rec.parks ADD COLUMN created_by varchar DEFAULT "current_user"();
ALTER TABLE parks_and_rec.parks ADD COLUMN date_modified timestamp with time zone;
ALTER TABLE parks_and_rec.parks ADD COLUMN modified_by varchar;

--Add a field to help differentiate between actual parks and proposed parks. 
ALTER TABLE parks_and_rec.parks ADD COLUMN status integer DEFAULT 1;


--Create a function that will be triggered when rows are added or updated. 
CREATE FUNCTION parks_and_rec.parks_trigger_function() RETURNS trigger AS $$

	BEGIN

			NEW.area_sqm = round(st_area(NEW.geom)::numeric,2);
			NEW.ward = (SELECT a.ward 
						from boundaries.municipal_election_wards_2018 a 
						WHERE st_intersects(a.geom,st_centroid(NEW.geom)));

			NEW.nearest_police_station = (
				WITH nearest_location AS (	
				SELECT b.station, min(st_distance(NEW.geom,b.geom)) as min_distance
				FROM services.police b
				GROUP BY b.station	
				ORDER BY min_distance
				LIMIT 1)
				SELECT station from nearest_location);

			NEW.nearest_police_station_distance_m = (
				SELECT round(min(st_distance(NEW.geom,b.geom))::numeric,2) as min_distance
				FROM services.police b
				ORDER BY min_distance
				LIMIT 1);
				
			NEW.nearest_hospital = (
				WITH nearest_location AS (	
				SELECT b.name, min(st_distance(NEW.geom,b.geom)) as min_distance
				FROM services.hospitals b
				GROUP BY b.name	
				ORDER BY min_distance
				LIMIT 1)
				SELECT name from nearest_location);

			NEW.nearest_hospital_distance_m = (
				SELECT round(min(st_distance(NEW.geom,b.geom))::numeric,2) as min_distance
				FROM services.hospitals b
				ORDER BY min_distance
				LIMIT 1);
				
			NEW.nearest_fire_station = (
				WITH nearest_location AS (	
				SELECT b.fire_hall, min(st_distance(NEW.geom,b.geom)) as min_distance
				FROM services.fire_stations b
				GROUP BY b.fire_hall	
				ORDER BY min_distance
				LIMIT 1)
				SELECT fire_hall from nearest_location);

			NEW.nearest_fire_station_distance_m = (
				SELECT round(min(st_distance(NEW.geom,b.geom))::numeric,2) as min_distance
				FROM services.fire_stations b
				ORDER BY min_distance
				LIMIT 1);

			NEW.date_modified = now(); 
			NEW.modified_by = "current_user"(); 

	RETURN NEW;
END;

$$ language plpgsql;

--Create the trigger on INSERT or UPDATE
CREATE TRIGGER parks_trigger
 BEFORE INSERT OR UPDATE
 ON parks_and_rec.parks
 FOR EACH ROW
 EXECUTE PROCEDURE parks_and_rec.parks_trigger_function();

--Update the table by making a change that will trigger the function.
UPDATE parks_and_rec.parks SET area_sqm = 0;

--Once styles are saved into public.layer_styles, you will need to grant access to this table with the following
--NOTE that this will only grant SELECT on this table. 
GRANT SELECT ON TABLE public.layer_styles TO editor;
GRANT SELECT ON TABLE public.layer_styles TO read_only;

--If you want to allow editors to change the default styles or save additional styles to the DB, run the following statement.
GRANT ALL ON TABLE public.layer_styles TO editor;

--To grant users read-only access to the projects in the map schema (or any other schema where projects live), run the following statement
GRANT SELECT ON TABLE maps.qgis_projects TO read_only;

--To grant users the ability to edit the project table, run the following statement
GRANT ALL ON TABLE maps.qgis_projects TO read_only;


