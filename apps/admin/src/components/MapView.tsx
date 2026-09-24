"use client";

import { useEffect, useRef } from "react";

const MAPBOX_STYLE = "mapbox://styles/mapbox/outdoors-v12";
const DEFAULT_CENTER: [number, number] = [2.3522, 48.8566]; // Paris

export type MapViewProps = {
  /** `[longitude, latitude]` pairs, e.g. an activity or segment route. */
  route?: [number, number][];
  className?: string;
};

/**
 * Mapbox GL JS map (ADR-012 §"Map"): route of a reported activity, segment
 * validation and correction. Client-only, specific to `apps/admin` —
 * `mapbox-gl` does not go into `packages/ui`.
 */
export function MapView({ route, className }: MapViewProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const token = process.env.NEXT_PUBLIC_MAPBOX_TOKEN;
    if (!containerRef.current || !token) {
      return;
    }

    let map: import("mapbox-gl").Map | undefined;
    let cancelled = false;

    void import("mapbox-gl").then(({ default: mapboxgl }) => {
      if (cancelled || !containerRef.current) {
        return;
      }

      mapboxgl.accessToken = token;
      map = new mapboxgl.Map({
        container: containerRef.current,
        style: MAPBOX_STYLE,
        center: route?.[0] ?? DEFAULT_CENTER,
        zoom: route ? 12 : 4,
      });

      if (route && route.length > 1) {
        map.on("load", () => {
          if (!map) return;
          map.addSource("route", {
            type: "geojson",
            data: {
              type: "Feature",
              properties: {},
              geometry: { type: "LineString", coordinates: route },
            },
          });
          map.addLayer({
            id: "route",
            type: "line",
            source: "route",
            layout: { "line-cap": "round", "line-join": "round" },
            paint: { "line-color": "#f97316", "line-width": 4 },
          });
        });
      }
    });

    return () => {
      cancelled = true;
      map?.remove();
    };
  }, [route]);

  if (!process.env.NEXT_PUBLIC_MAPBOX_TOKEN) {
    return (
      <div className="flex h-full min-h-64 items-center justify-center rounded-md border border-dashed text-sm text-muted-foreground">
        Carte indisponible (NEXT_PUBLIC_MAPBOX_TOKEN manquant)
      </div>
    );
  }

  return <div ref={containerRef} className={className ?? "h-full min-h-64 w-full rounded-md"} />;
}
