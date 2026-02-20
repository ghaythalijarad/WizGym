import { Body, Controller, Get, Param, Post } from '@nestjs/common';

import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { RequestUser } from '../../common/interfaces/request-user.interface';
import { CreateTrainerRatingDto } from './dto/create-trainer-rating.dto';
import { TrainersService } from './trainers.service';

@Controller('trainers')
export class TrainersController {
  constructor(private readonly trainersService: TrainersService) {}

  @Get('me/clients')
  @Roles(Role.TRAINER)
  getMyClients(@CurrentUser() user: RequestUser) {
    return this.trainersService.getMyClients(user.id);
  }

  @Get('me/gyms')
  @Roles(Role.TRAINER)
  getMyGyms(@CurrentUser() user: RequestUser) {
    return this.trainersService.getMyGyms(user.id);
  }

  @Post(':trainerId/ratings')
  @Roles(Role.USER)
  rateTrainer(
    @Param('trainerId') trainerId: string,
    @CurrentUser() user: RequestUser,
    @Body() body: CreateTrainerRatingDto,
  ) {
    return this.trainersService.rateTrainer(user.id, trainerId, body);
  }

  @Get(':trainerId/ratings')
  trainerRatings(@Param('trainerId') trainerId: string) {
    return this.trainersService.getTrainerRatings(trainerId);
  }
}
