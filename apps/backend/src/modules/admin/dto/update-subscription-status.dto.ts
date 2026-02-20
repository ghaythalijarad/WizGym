import { IsIn } from 'class-validator';

import { SubscriptionStatus } from '../admin.types';

const subscriptionStatuses: SubscriptionStatus[] = ['ACTIVE', 'PAUSED', 'CANCELED'];

export class UpdateSubscriptionStatusDto {
  @IsIn(subscriptionStatuses)
  status!: SubscriptionStatus;
}
