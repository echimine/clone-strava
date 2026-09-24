import { Module } from "@nestjs/common";
import { ConfigModule } from "../config/config.module.js";
import { RedisModule } from "../redis/redis.module.js";
import { GatewayService } from "./gateway.service.js";

@Module({
  imports: [ConfigModule, RedisModule],
  providers: [GatewayService],
  exports: [GatewayService],
})
export class GatewayModule {}
