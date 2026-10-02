/** Average and maximum heart rate over the points that have one (ADR-019 §5 step 4). */
export function computeHeartRate(points: Array<{ heartRateBpm?: number }>): {
  avgHeartRate?: number;
  maxHeartRate?: number;
} {
  let sum = 0;
  let count = 0;
  let max = 0;
  for (const point of points) {
    if (point.heartRateBpm !== undefined && point.heartRateBpm > 0) {
      sum += point.heartRateBpm;
      count++;
      max = Math.max(max, point.heartRateBpm);
    }
  }
  return count === 0 ? {} : { avgHeartRate: Math.round(sum / count), maxHeartRate: max };
}
