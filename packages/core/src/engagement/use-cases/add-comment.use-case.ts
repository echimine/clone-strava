import { Injectable, NotImplementedException } from "@nestjs/common";
import { CommentRepository } from "../repositories/comment.repository.js";

@Injectable()
export class AddCommentUseCase {
  constructor(private readonly comments: CommentRepository) {}

  async execute(_userId: string, _activityId: string, _body: string): Promise<void> {
    throw new NotImplementedException();
  }
}
