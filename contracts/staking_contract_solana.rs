use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};

declare_id!("Stak1ngPr0gramHere111111111111111111111111");

#[program]
pub mod staking_contract {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        reward_rate: u64,
        minimum_staking_period: i64,
    ) -> Result<()> {
        let staking_state = &mut ctx.accounts.staking_state;
        staking_state.owner = ctx.accounts.owner.key();
        staking_state.reward_rate = reward_rate;
        staking_state.minimum_staking_period = minimum_staking_period;
        staking_state.last_update_time = Clock::get()?.unix_timestamp;
        staking_state.acc_reward_per_share = 0;
        staking_state.total_staked = 0;
        Ok(())
    }

    pub fn stake(ctx: Context<Stake>, amount: u64) -> Result<()> {
        let staking_state = &mut ctx.accounts.staking_state;
        let stake_info = &mut ctx.accounts.stake_info;

        // Update rewards
        update_rewards(staking_state)?;

        // Transfer tokens from user to staking contract
        let cpi_accounts = Transfer {
            from: ctx.accounts.user_token_account.to_account_info(),
            to: ctx.accounts.staking_token_account.to_account_info(),
            authority: ctx.accounts.user.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
        );
        token::transfer(cpi_ctx, amount)?;

        // Update stake info
        if stake_info.amount == 0 {
            stake_info.start_time = Clock::get()?.unix_timestamp;
        }
        stake_info.amount = stake_info.amount.checked_add(amount).unwrap();
        stake_info.reward_debt = (stake_info.amount as u128)
            .checked_mul(staking_state.acc_reward_per_share)
            .unwrap()
            .checked_div(PRECISION_FACTOR)
            .unwrap() as u64;

        // Update total staked
        staking_state.total_staked = staking_state.total_staked.checked_add(amount).unwrap();

        emit!(Staked {
            user: ctx.accounts.user.key(),
            amount,
        });

        Ok(())
    }

    pub fn unstake(ctx: Context<Unstake>, amount: u64) -> Result<()> {
        let staking_state = &mut ctx.accounts.staking_state;
        let stake_info = &mut ctx.accounts.stake_info;

        require!(
            stake_info.amount >= amount,
            StakingError::InsufficientStakedAmount
        );
        require!(
            Clock::get()?.unix_timestamp >= stake_info.start_time + staking_state.minimum_staking_period,
            StakingError::MinimumStakingPeriodNotReached
        );

        // Update rewards
        update_rewards(staking_state)?;

        // Update stake info
        stake_info.amount = stake_info.amount.checked_sub(amount).unwrap();
        stake_info.reward_debt = (stake_info.amount as u128)
            .checked_mul(staking_state.acc_reward_per_share)
            .unwrap()
            .checked_div(PRECISION_FACTOR)
            .unwrap() as u64;

        // Update total staked
        staking_state.total_staked = staking_state.total_staked.checked_sub(amount).unwrap();

        // Transfer tokens back to user
        let cpi_accounts = Transfer {
            from: ctx.accounts.staking_token_account.to_account_info(),
            to: ctx.accounts.user_token_account.to_account_info(),
            authority: ctx.accounts.staking_state.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
        );
        token::transfer(cpi_ctx, amount)?;

        emit!(Unstaked {
            user: ctx.accounts.user.key(),
            amount,
        });

        Ok(())
    }

    pub fn claim_rewards(ctx: Context<ClaimRewards>) -> Result<()> {
        let staking_state = &mut ctx.accounts.staking_state;
        let stake_info = &mut ctx.accounts.stake_info;

        // Update rewards
        update_rewards(staking_state)?;

        // Calculate pending rewards
        let pending = (stake_info.amount as u128)
            .checked_mul(staking_state.acc_reward_per_share)
            .unwrap()
            .checked_div(PRECISION_FACTOR)
            .unwrap()
            .checked_sub(stake_info.reward_debt as u128)
            .unwrap() as u64;

        if pending > 0 {
            // Transfer rewards to user
            let cpi_accounts = Transfer {
                from: ctx.accounts.staking_token_account.to_account_info(),
                to: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.staking_state.to_account_info(),
            };
            let cpi_ctx = CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                cpi_accounts,
            );
            token::transfer(cpi_ctx, pending)?;

            emit!(RewardPaid {
                user: ctx.accounts.user.key(),
                reward: pending,
            });
        }

        // Update reward debt
        stake_info.reward_debt = (stake_info.amount as u128)
            .checked_mul(staking_state.acc_reward_per_share)
            .unwrap()
            .checked_div(PRECISION_FACTOR)
            .unwrap() as u64;

        Ok(())
    }

    pub fn update_reward_rate(ctx: Context<UpdateRewardRate>, new_rate: u64) -> Result<()> {
        let staking_state = &mut ctx.accounts.staking_state;
        require!(
            ctx.accounts.owner.key() == staking_state.owner,
            StakingError::Unauthorized
        );

        // Update rewards before changing rate
        update_rewards(staking_state)?;
        staking_state.reward_rate = new_rate;

        emit!(RewardRateUpdated { new_rate });

        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = owner,
        space = 8 + StakingState::LEN
    )]
    pub staking_state: Account<'info, StakingState>,
    #[account(mut)]
    pub owner: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut)]
    pub staking_state: Account<'info, StakingState>,
    #[account(
        init_if_needed,
        payer = user,
        space = 8 + StakeInfo::LEN
    )]
    pub stake_info: Account<'info, StakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub staking_token_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Unstake<'info> {
    #[account(mut)]
    pub staking_state: Account<'info, StakingState>,
    #[account(mut)]
    pub stake_info: Account<'info, StakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub staking_token_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct ClaimRewards<'info> {
    #[account(mut)]
    pub staking_state: Account<'info, StakingState>,
    #[account(mut)]
    pub stake_info: Account<'info, StakeInfo>,
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(mut)]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub staking_token_account: Account<'info, TokenAccount>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct UpdateRewardRate<'info> {
    #[account(mut)]
    pub staking_state: Account<'info, StakingState>,
    pub owner: Signer<'info>,
}

#[account]
pub struct StakingState {
    pub owner: Pubkey,
    pub reward_rate: u64,
    pub minimum_staking_period: i64,
    pub last_update_time: i64,
    pub acc_reward_per_share: u64,
    pub total_staked: u64,
}

#[account]
pub struct StakeInfo {
    pub amount: u64,
    pub start_time: i64,
    pub reward_debt: u64,
}

const PRECISION_FACTOR: u128 = 1_000_000_000_000;

#[error_code]
pub enum StakingError {
    #[msg("Insufficient staked amount")]
    InsufficientStakedAmount,
    #[msg("Minimum staking period not reached")]
    MinimumStakingPeriodNotReached,
    #[msg("Unauthorized")]
    Unauthorized,
}

#[event]
pub struct Staked {
    pub user: Pubkey,
    pub amount: u64,
}

#[event]
pub struct Unstaked {
    pub user: Pubkey,
    pub amount: u64,
}

#[event]
pub struct RewardPaid {
    pub user: Pubkey,
    pub reward: u64,
}

#[event]
pub struct RewardRateUpdated {
    pub new_rate: u64,
}

fn update_rewards(staking_state: &mut Account<StakingState>) -> Result<()> {
    if staking_state.total_staked > 0 {
        let current_time = Clock::get()?.unix_timestamp;
        let time_diff = current_time - staking_state.last_update_time;
        if time_diff > 0 {
            let reward = (time_diff as u128)
                .checked_mul(staking_state.reward_rate as u128)
                .unwrap();
            staking_state.acc_reward_per_share = staking_state
                .acc_reward_per_share
                .checked_add(
                    (reward.checked_mul(PRECISION_FACTOR).unwrap())
                        .checked_div(staking_state.total_staked as u128)
                        .unwrap() as u64,
                )
                .unwrap();
        }
        staking_state.last_update_time = current_time;
    }
    Ok(())
} 