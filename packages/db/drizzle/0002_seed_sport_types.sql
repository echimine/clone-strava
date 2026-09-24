-- Reference data (ADR-017: `sport_type`, "populated by migration").
-- Values are reasonable MVP defaults; icon names are placeholders for the
-- iOS SF Symbol the mobile app will use per sport (ADR-006/ADR-007).
INSERT INTO "sports"."sport_type"
  ("code", "category", "icon_name", "tracks_distance", "tracks_elevation", "uses_gps", "pace_unit", "min_duration_s", "min_distance_m", "display_order", "is_active")
VALUES
  ('run', 'foot', 'figure.run', true, true, true, 'pace', 60, 100, 1, true),
  ('ride', 'wheels', 'bicycle', true, true, true, 'speed', 60, 200, 2, true),
  ('swim', 'water', 'figure.pool.swim', true, false, false, 'pace', 60, 50, 3, true),
  ('walk', 'foot', 'figure.walk', true, true, true, 'pace', 60, 100, 4, true),
  ('hike', 'foot', 'figure.hiking', true, true, true, 'pace', 300, 200, 5, true);
