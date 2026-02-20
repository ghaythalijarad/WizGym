import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';

import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { Role } from '../../common/enums/role.enum';
import { RequestUser } from '../../common/interfaces/request-user.interface';
import { CreateGymFacilityDto } from './dto/create-gym-facility.dto';
import { CreateGymProductDto } from './dto/create-gym-product.dto';
import { CreateGymRatingDto } from './dto/create-gym-rating.dto';
import { UpdateGymProfileDto } from './dto/update-gym-profile.dto';
import { GymsService } from './gyms.service';

@Controller('gyms')
export class GymsController {
  constructor(private readonly gymsService: GymsService) {}

  @Get('public')
  publicGyms(@Query('city') city?: string, @Query('audience') audience?: string) {
    return this.gymsService.listPublicGyms(city, audience);
  }

  @Get('owner/dashboard')
  @Roles(Role.OWNER)
  ownerDashboard(@CurrentUser() user: RequestUser) {
    return this.gymsService.ownerDashboard(user.id);
  }

  @Get('owner/mine')
  @Roles(Role.OWNER)
  ownerGyms(@CurrentUser() user: RequestUser) {
    return this.gymsService.listOwnerGyms(user.id);
  }

  @Get(':gymId/public')
  publicGymDetails(@Param('gymId') gymId: string) {
    return this.gymsService.getPublicGymDetails(gymId);
  }

  @Post(':gymId/join')
  @Roles(Role.USER)
  joinGym(@Param('gymId') gymId: string, @CurrentUser() user: RequestUser) {
    return this.gymsService.joinGymAsUser(gymId, user.id);
  }

  @Post(':gymId/trainers/join')
  @Roles(Role.TRAINER)
  joinGymAsTrainer(@Param('gymId') gymId: string, @CurrentUser() user: RequestUser) {
    return this.gymsService.joinGymAsTrainer(gymId, user.id);
  }

  @Get(':gymId/trainers')
  @Roles(Role.USER, Role.TRAINER, Role.OWNER, Role.ADMIN)
  gymTrainers(@Param('gymId') gymId: string, @CurrentUser() user: RequestUser) {
    return this.gymsService.listGymTrainers(gymId, user);
  }

  @Post(':gymId/trainers/:trainerId/hire')
  @Roles(Role.USER)
  hireTrainer(
    @Param('gymId') gymId: string,
    @Param('trainerId') trainerId: string,
    @CurrentUser() user: RequestUser,
  ) {
    return this.gymsService.hireTrainer(gymId, trainerId, user.id);
  }

  @Post(':gymId/ratings')
  @Roles(Role.USER)
  rateGym(
    @Param('gymId') gymId: string,
    @CurrentUser() user: RequestUser,
    @Body() body: CreateGymRatingDto,
  ) {
    return this.gymsService.rateGym(gymId, user.id, body);
  }

  @Get(':gymId/ratings')
  gymRatings(@Param('gymId') gymId: string) {
    return this.gymsService.getGymRatings(gymId);
  }

  @Get(':gymId/facilities/public')
  facilities(@Param('gymId') gymId: string) {
    return this.gymsService.listFacilities(gymId);
  }

  @Post(':gymId/facilities')
  @Roles(Role.OWNER)
  createFacility(
    @Param('gymId') gymId: string,
    @CurrentUser() user: RequestUser,
    @Body() body: CreateGymFacilityDto,
  ) {
    return this.gymsService.createFacility(gymId, user.id, body);
  }

  @Get(':gymId/products/public')
  products(@Param('gymId') gymId: string) {
    return this.gymsService.listProducts(gymId);
  }

  @Post(':gymId/products')
  @Roles(Role.OWNER)
  createProduct(
    @Param('gymId') gymId: string,
    @CurrentUser() user: RequestUser,
    @Body() body: CreateGymProductDto,
  ) {
    return this.gymsService.createProduct(gymId, user.id, body);
  }

  @Patch(':gymId/profile')
  @Roles(Role.OWNER)
  updateGymProfile(
    @Param('gymId') gymId: string,
    @CurrentUser() user: RequestUser,
    @Body() body: UpdateGymProfileDto,
  ) {
    return this.gymsService.updateGymProfile(gymId, user.id, body);
  }
}
