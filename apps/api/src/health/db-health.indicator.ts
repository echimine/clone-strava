import { Inject, Injectable } from "@nestjs/common";
import { HealthIndicatorService } from "@nestjs/terminus";
import { DATABASE, type Database } from "@repo/core/infrastructure";

@Injectable()
export class DbHealthIndicator {
  constructor(
    private readonly healthIndicatorService: HealthIndicatorService,
    @Inject(DATABASE) private readonly db: Database,
  ) {}

  async isHealthy(key: string) {
    const indicator = this.healthIndicatorService.check(key);
    try {
      // A plain string is accepted by `db.execute` (node-postgres driver);
      // no need for the `sql` tag here, which would pull `drizzle-orm` in
      // as a direct dependency of this app.
      await this.db.execute("select 1");
      return indicator.up();
    } catch (error) {
      return indicator.down(error instanceof Error ? error.message : "unknown error");
    }
  }
}
