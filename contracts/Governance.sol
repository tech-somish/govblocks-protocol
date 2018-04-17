/* Copyright (C) 2017 GovBlocks.io

  This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

  This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
    along with this program.  If not, see http://www.gnu.org/licenses/ */


pragma solidity ^0.4.8;
import "./governanceData.sol";
import "./ProposalCategory.sol";
import "./memberRoles.sol";
import "./Master.sol";
import "./BasicToken.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./Pool.sol";
import "./GBTController.sol";
import "./GBTStandardToken.sol";
import "./VotingType.sol";

contract Governance {
    
  using SafeMath for uint;
  using Math for uint;
  address GDAddress;
  address PCAddress;
  address MRAddress;
  address masterAddress;
  address BTAddress;
  address P1Address;
  address GBTCAddress;
  address GBTSAddress;
  GBTStandardToken GBTS;
  GBTController GBTC;
  Master MS;
  memberRoles MR;
  ProposalCategory PC;
  governanceData GD;
  BasicToken BT;
  Pool P1;
  VotingType VT;
  uint finalRewardToDistribute;

    modifier onlyInternal {
        MS=Master(masterAddress);
        require(MS.isInternal(msg.sender) == 1);
        _; 
    }
    
     modifier onlyOwner{
        MS=Master(masterAddress);
        require(MS.isOwner(msg.sender) == 1);
        _; 
    }

    modifier onlyMaster {    
        require(msg.sender == masterAddress);
        _; 
    }


  function changeAllContractsAddress(address _GDContractAddress,address _MRContractAddress,address _PCContractAddress,address _PoolContractAddress) onlyInternal
  {
     GDAddress = _GDContractAddress;
     PCAddress = _PCContractAddress;
     MRAddress = _MRContractAddress;
     P1Address = _PoolContractAddress;
  }

  function changeGBTControllerAddress(address _GBTCAddress) onlyMaster
  {
     GBTCAddress = _GBTCAddress;
  }
  
  function changeGBTSAddress(address _GBTAddress) onlyMaster
    {
        GBTSAddress = _GBTAddress;
    }

  function changeMasterAddress(address _MasterAddress) onlyInternal
  {
    if(masterAddress == 0x000)
        masterAddress = _MasterAddress;
    else
    {
        MS=Master(masterAddress);
        require(MS.isInternal(msg.sender) == 1);
          masterAddress = _MasterAddress;
    }
  }
  
  function createProposal(string _proposalDescHash,uint _votingTypeId,uint8 _categoryId,uint _dateAdd) public
  {
      GD=governanceData(GDAddress);
      PC=ProposalCategory(PCAddress);
      uint _proposalId = GD.getProposalLength();
      address votingAddress = GD.getVotingTypeAddress(_votingTypeId); 

      if(_categoryId > 0)
      {
          GD.addTotalProposal(_proposalId,msg.sender);
          GD.addNewProposal(_proposalId,msg.sender,_proposalDescHash,_categoryId,votingAddress,_dateAdd);
          GD.setProposalIncentive(_proposalId,PC.getCatIncentive(_categoryId));
          // addInitialOptionDetails(_proposalId);
          // GD.setCategorizedBy(_proposalId,msg.sender);
      }
      else
      {
          GD.addTotalProposal(_proposalId,msg.sender);
          GD.createProposal1(_proposalId,msg.sender,_proposalDescHash,votingAddress,now);          
      }
  }

  /// @dev Creates a new proposal.
  function createProposalwithOption(string _proposalDescHash,uint _votingTypeId,uint8 _categoryId,uint _TokenAmount,string _optionHash) public
  {
      GD=governanceData(GDAddress);
      uint nowDate = now;
      uint _proposalId = GD.getProposalLength();
      address VTAddress = GD.getVotingTypeAddress(_votingTypeId);
      VT=VotingType(VTAddress);

      uint proposalGBT = SafeMath.div(_TokenAmount,2);
      receiveStakeInGbt(_proposalId,SafeMath.sub(_TokenAmount,proposalGBT),PC.getCatIncentive(_categoryId));
      createProposal(_proposalDescHash,_votingTypeId,_categoryId,nowDate);
      VT.addVerdictOption(_proposalId,msg.sender,_optionHash,nowDate);
      openProposalForVoting(_proposalId,_categoryId,_TokenAmount);
  }

  function receiveStakeInGbt(uint _proposalId,uint _optionGBT,uint _Incentive) internal
  {
        // receiveGBT(gbtTransfer,"Payable GBT Stake to submit proposal for voting");
        // receiveGBT(amount,"Payable GBT Stake for adding solution against proposal");
        // receiveGBT(_Incentive,"Dapp incentive to be distributed in GBT")
        uint depositAmount = ((_optionGBT*GD.depositPercOption())/100);
        uint finalAmount = depositAmount + GD.getDepositTokensByAddress(msg.sender,_proposalId);
        GD.setDepositTokens(msg.sender,_proposalId,finalAmount,'S');
        GBTS.lockMemberToken(_gbUserName,_proposalId,SafeMath.sub(_optionGBT,finalAmount));
  }

  function submitProposalWithOption(uint _proposalId,uint _TokenAmount,string _optionHash)
  {
      GD=governanceData(GDAddress); 
      require(msg.sender == GD.getProposalOwner(_proposalId));

      uint proposalGBT = SafeMath.div(_TokenAmount,2);
      openProposalForVoting(_proposalId,GD.getProposalCategory(_proposalId),_TokenAmount);
      VT=VotingType(GD.getProposalVotingType(_proposalId));
      uint nowDate = GD.getProposalDateAdd(_proposalId);

      receiveStakeInGbt(_proposalId,SafeMath.sub(_TokenAmount,proposalGBT),PC.getCatIncentive(GD.getProposalCategory(_proposalId)));
      VT.addVerdictOption(_proposalId,msg.sender,_optionHash,nowDate); 
  }

  function openProposalForVoting(uint _proposalId,uint _categoryId,uint _tokenAmount) 
  {
      PC = ProposalCategory(PCAddress);
      GD = governanceData(GDAddress);
      P1 = Pool(P1Address);
      GBTS=GBTStandardToken(GBTSAddress);

      require(GD.getProposalCategory(_proposalId) != 0 && GD.getProposalStatus(_proposalId) < 2);
      require(GD.getProposalOwner(_proposalId) == msg.sender);
      uint closingTime = SafeMath.add(PC.getClosingTimeAtIndex(_categoryId,0),GD.getProposalDateUpd(_proposalId));
      GD.changeProposalStatus(_proposalId,2);
      callOraclize(_proposalId,closingTime);

      uint depositAmount = SafeMath.div(SafeMath.mul(_TokenAmount,GD.depositPercProposal()),100);
      uint finalAmount = depositAmount + GD.getDepositTokensByAddress(msg.sender,_proposalId);
      GBTS.lockMemberToken(_gbUserName,_proposalId,SafeMath.sub(_TokenAmount,finalAmount));
      GD.setDepositTokens(msg.sender,_proposalId,finalAmount,'P');
      GD.setProposalStake(_proposalId,_memberStake);
  }

  function callOraclize(uint _proposalId,uint _closeTime)
  {
      GD = governanceData(GDAddress);
      P1 = Pool(P1Address);
      P1.closeProposalOraclise(_proposalId,_closeTime);
      GD.callOraclizeCallEvent(_proposalId,GD.getProposalDateAdd(_proposalId),_closeTime);
  }

  /// @dev Edits a proposal and Only owner of a proposal can edit it.
  function editProposal(uint _proposalId ,string _proposalDescHash) public
  {
      GD=governanceData(GDAddress);
      require(msg.sender == GD.getProposalOwner(_proposalId));
      GD.storeProposalVersion(_proposalId,_proposalDescHash);
      updateProposalDetails1(_proposalId,_proposalDescHash);
      GD.changeProposalStatus(_proposalId,1);
      
      if(GD.getProposalCategory(_proposalId) > 0)
        GD.setProposalCategory(_proposalId,0);
  }
  
  /// @dev categorizing proposal to proceed further. _reward is the company incentive to distribute to End Members.
  function categorizeProposal(uint _proposalId , uint8 _categoryId,uint8 _proposalComplexityLevel,uint _dappIncentive) public
  {
      MR = memberRoles(MRAddress);
      GD = governanceData(GDAddress);
      P1 = Pool(P1Address);
      GBTS=GBTStandardToken(GBTSAddress);

      require(MR.getMemberRoleIdByAddress(msg.sender) == MR.getAuthorizedMemberId());
      require(GD.getProposalStatus(_proposalId) == 1 || GD.getProposalStatus(_proposalId) == 0);
      
      addComplexityLevelAndIncentive(_proposalId,_categoryId,_proposalComplexityLevel,_dappIncentive);
      // addInitialOptionDetails(_proposalId);
      
      if(_dappIncentive != 0)
      {
        uint gbtBalanceOfPool = GBTS.balanceOf(P1Address);
        require (gbtBalanceOfPool >= _dappIncentive);
      }
       
      GD.setProposalIncentive(_proposalId,_dappIncentive);
      GD.setCategorizedBy(_proposalId,msg.sender);
      GD.setProposalCategory(_proposalId,_categoryId);
  }

  /// @dev Proposal's complexity level and reward is added 
  function addComplexityLevelAndIncentive(uint _proposalId,uint _category,uint8 _proposalComplexityLevel,uint _reward) internal
  {
      GD=governanceData(GDAddress);
      GD.setProposalLevel(_proposalId,_proposalComplexityLevel);
      GD.setProposalIncentive(_proposalId,_reward); 
  }


  /// @dev AFter the proposal final decision, member reputation will get updated.
  function updateMemberReputation(uint _proposalId,uint _finalVerdict) onlyInternal
  {
    GD=governanceData(GDAddress);
    address _proposalOwner =  GD.getProposalOwner(_proposalId);
    address _finalOptionOwner = GD.getOptionAddressByProposalId(_proposalId,_finalVerdict);
    uint addProposalOwnerPoints; uint addOptionOwnerPoints; uint subProposalOwnerPoints; uint subOptionOwnerPoints;
    (addProposalOwnerPoints,addOptionOwnerPoints,,subProposalOwnerPoints,subOptionOwnerPoints,)= GD.getMemberReputationPoints();

    if(_finalVerdict>0)
    {
        GD.setMemberReputation("Reputation credit for proposal owner - Accepted",_proposalId,_proposalOwner,SafeMath.add(GD.getMemberReputation(_proposalOwner),addProposalOwnerPoints),addProposalOwnerPoints,"C");
        GD.setMemberReputation("Reputation credit for option owner - Final option selected by majority voting",_proposalId,_finalOptionOwner,SafeMath.add(GD.getMemberReputation(_finalOptionOwner),addOptionOwnerPoints),addOptionOwnerPoints,"C"); 
    }
    else
    {
        GD.setMemberReputation("Reputation debit for proposal owner - Rejected",_proposalId,_proposalOwner,SafeMath.sub(GD.getMemberReputation(_proposalOwner),subProposalOwnerPoints),subProposalOwnerPoints,"D");
        for(uint i=0; i<GD.getOptionAddedAddressLength(_proposalId); i++)
        {
            address memberAddress = GD.getOptionAddressByProposalId(_proposalId,i);
            GD.setMemberReputation("Reputation debit for option owner - Rejected by majority voting",_proposalId,memberAddress,SafeMath.sub(GD.getMemberReputation(memberAddress),subOptionOwnerPoints),subOptionOwnerPoints,"D");
        }
    }   
  }

  /// @dev Afer proposal Final Decision, Member reputation will get updated.
  function updateMemberReputation1(string _desc,uint _proposalId,address _voterAddress,uint _voterPoints,uint _repPointsEvent,bytes4 _typeOf) onlyInternal
  {
     GD=governanceData(GDAddress);
     GD.setMemberReputation(_desc,_proposalId,_voterAddress,_voterPoints,_repPointsEvent,_typeOf);
  }

  function checkProposalVoteClosing(uint _proposalId,uint _roleId,uint _closingTime,uint _majorityVote) onlyInternal constant returns(uint8 closeValue) 
  {
      GD=governanceData(GDAddress);
      MR=memberRoles(MRAddress);
      uint dateUpdate;
      (,,,,dateUpdate,,) = GD.getProposalDetailsById1(_proposalId);

      if(GD.getProposalStatus(_proposalId) == 2 && _roleId != 2)
      {
        if(SafeMath.add(dateUpdate,_closingTime) <= now || GD.getVoteLength(_proposalId,_roleId) == MR.getAllMemberLength(_roleId))
          closeValue=1;
      }
      else if(GD.getProposalStatus(_proposalId) == 2)
      {
         if(SafeMath.add(dateUpdate,_closingTime) <= now)
              closeValue=1;
      }
      else if(GD.getProposalStatus(_proposalId) > 2)
      {
         closeValue=2;
      }
      else
      {
        closeValue=0;
      }
  }

  function checkRoleVoteClosing(uint _proposalId,uint _roleId,uint _closingTime,uint _majorityVote) onlyInternal
  {    
    if(checkProposalVoteClosing(_proposalId,_roleId,_closingTime,_majorityVote)==1)
          callOraclize(_proposalId,0);
  }

    function getStatusOfProposalsForMember(uint[] _proposalsIds)constant returns (uint proposalLength,uint draftProposals,uint pendingProposals,uint acceptedProposals,uint rejectedProposals)
    {
        GD=governanceData(GDAddress);
        uint proposalStatus;
        proposalLength=GD.getProposalLength();

         for(uint i=0;i<_proposalsIds.length; i++)
         {
           proposalStatus=GD.getProposalStatus(_proposalsIds[i]);
           if(proposalStatus<2)
               draftProposals++;
           else if(proposalStatus==2)
             pendingProposals++;
           else if(proposalStatus==3)
             acceptedProposals++;
           else if(proposalStatus>=4)
             rejectedProposals++;
         }
   }
 
  //get status of proposals
  function getStatusOfProposals()constant returns (uint _proposalLength,uint _draftProposals,uint _pendingProposals,uint _acceptedProposals,uint _rejectedProposals)
  {
    GD=governanceData(GDAddress);
    uint proposalStatus;
    _proposalLength=GD.getProposalLength();

    for(uint i=0;i<_proposalLength;i++){
      proposalStatus=GD.getProposalStatus(i);
      if(proposalStatus<2)
          _draftProposals++;
      else if(proposalStatus==2)
        _pendingProposals++;
      else if(proposalStatus==3)
        _acceptedProposals++;
      else if(proposalStatus>=4)
        _rejectedProposals++;
        }
  }

    function getVoteDetailById(address _memberAddress,address _votingTypeAddress,uint _voteId)constant returns(uint id, uint proposalId,uint dateAdded,uint voteStake,uint voteReward)
    {
        id = _voteId;
        VT=VotingType(_votingTypeAddress);
        GD=governanceData(GDAddress);
        require(GD.getVoterAddress(_voteId) == _memberAddress);
          (,proposalId,,dateAdded,,voteStake,) = GD.getVoteDetailByid(_voteId);
          voteReward = GD.getVoteReward(_voteId); 
    } 

    /// @dev Get the Value, stake and Address of the member whosoever added that verdict option.
    function getOptionDetailsById(uint _proposalId,uint _optionIndex) constant returns(uint id, uint optionid,uint optionStake,uint optionValue,address memberAddress,uint optionReward)
    {
        GD=governanceData(GDAddress);
        id = _proposalId;
        optionid = _optionIndex;
        optionStake = GD.getOptionStakeById(_proposalId,_optionIndex);
        optionValue = GD.getOptionValueByProposalId(_proposalId,_optionIndex);
        memberAddress = GD.getOptionAddressByProposalId(_proposalId,_optionIndex);
        optionReward = GD.getOptionReward(_proposalId,_optionIndex);
        return (_proposalId,optionid,optionStake,optionValue,memberAddress,optionReward);
    }

    function getOptionDetailsByAddress(uint _proposalId,address _memberAddress) constant returns(uint optionIndex,uint optionStake,uint optionReward,uint dateAdded,uint proposalId)
    {
        GD=governanceData(GDAddress);
        optionIndex = GD.getOptionIdByAddress(_proposalId,_memberAddress);
        optionStake = GD.getOptionStakeById(_proposalId,optionIndex);
        optionReward = GD.getOptionReward(_proposalId,optionIndex);
        dateAdded = GD.getOptionDateAdded(_proposalId,optionIndex);
        proposalId = _proposalId;    
    }

    function getProposalRewardByMember(address _memberAddress) constant returns(uint[] propStake,uint[] propReward)
    {
        GD=governanceData(GDAddress);
        propStake = new uint[](GD.getTotalProposal(_memberAddress));
        propReward = new uint[](GD.getTotalProposal(_memberAddress));

        for(uint i=0; i<GD.getTotalProposal(_memberAddress); i++)
        {
            propStake[i] = GD.getProposalStake(GD.getProposalIdByAddress(_memberAddress,i));
            propReward[i] = GD.getProposalReward(GD.getProposalIdByAddress(_memberAddress,i));
        }
    }

    function getProposalStakeByMember(address _memberAddress) constant returns(uint stakeValueProposal)
    {
        GD=governanceData(GDAddress);
        for(uint i=0; i<GD.getTotalProposal(_memberAddress); i++)
        {
            stakeValueProposal = stakeValueProposal + GD.getProposalStake(GD.getProposalIdByAddress(_memberAddress,i));
        }
    }

    function getOptionStakeByMember(address _memberAddress)constant returns(uint stakeValueOption)
    {
        GD=governanceData(GDAddress); stakeValueOption;

        for(uint i=0; i<GD.getProposalAnsLength(_memberAddress); i++)
        {
            uint _proposalId = GD.getProposalAnsId(_memberAddress,i);
            uint _optionId = GD.getOptionIdByAddress(_proposalId,_memberAddress);
            uint stake = GD.getOptionStakeById(_proposalId,_optionId);
            stakeValueOption = stakeValueOption + stake;
        }
    }

    function setProposalDetails(uint _proposalId,uint _totaltoken,uint _blockNumber,uint _totalVoteValue) onlyInternal
    {
       GD=governanceData(GDAddress);
       GD.setProposalTotalToken(_proposalId,_totaltoken);
       GD.setProposalBlockNo(_proposalId,_blockNumber);
       GD.setProposalTotalVoteValue(_proposalId,_totalVoteValue);
    }

    function getMemberDetails(address _memberAddress) constant returns(uint memberReputation, uint totalProposal,uint proposalStake,uint totalOption,uint optionStake,uint totalVotes)
    {
        GD=governanceData(GDAddress);
        memberReputation = GD.getMemberReputation(_memberAddress);
        totalProposal = GD.getTotalProposal(_memberAddress);
        proposalStake = getProposalStakeByMember(_memberAddress);
        totalOption = GD.getProposalAnsLength(_memberAddress);
        optionStake = getOptionStakeByMember(_memberAddress);
        totalVotes = GD.getTotalVotesByAddress(_memberAddress);
    }

    // /// @dev As bydefault first option is alwayd deny option. One time configurable.
    // function addInitialOptionDetails(uint _proposalId) internal
    // {
    //     GD=governanceData(GDAddress);
    //     if(GD.getInitialOptionsAdded(_proposalId) == 0)
    //     {
    //         GD.setOptionAddress(_proposalId,0x00);
    //         GD.setOptionStake(_proposalId,0);
    //         GD.setOptionValue(_proposalId,0);
    //         GD.setOptionHash(_proposalId,"");
    //         GD.setOptionDateAdded(_proposalId,0);
    //         GD.setTotalOptions(_proposalId);
    //         GD.setInitialOptionsAdded(_proposalId);
    //     }
    // }

    /// @dev Change pending proposal start variable
    function changePendingProposalStart() onlyInternal
    {
        GD=governanceData(GDAddress);
        uint pendingPS = GD.pendingProposalStart();
        for(uint j=pendingPS; j<GD.getProposalLength(); j++)
        {
            if(GD.getProposalStatus(j) > 3)
                pendingPS = SafeMath.add(pendingPS,1);
            else
                break;
        }
        if(j!=pendingPS)
        {
            GD.changePendingProposalStart(j);
        }
    }
    /// @dev Updating proposal's Major details (Called from close proposal Vote).
    function updateProposalDetails(uint _proposalId,uint8 _currVotingStatus, uint8 _intermediateVerdict,uint8 _finalVerdict) onlyInternal 
    {
        GD=governanceData(GDAddress);
        GD.setProposalCurrentVotingId(_proposalId,_currVotingStatus);
        GD.setProposalIntermediateVerdict(_proposalId,_intermediateVerdict);
        GD.setProposalFinalVerdict(_proposalId,_finalVerdict);
        GD.setProposalDateUpd(_proposalId);
    }

    /// @dev Edits the details of an existing proposal and creates new version.
    function updateProposalDetails1(uint _proposalId,string _proposalDescHash) internal
    {
        GD=governanceData(GDAddress);
        GD.setProposalDesc(_proposalId,_proposalDescHash);
        GD.setProposalDateUpd(_proposalId);
        GD.setProposalVersion(_proposalId);
    }

    function getTotalIncentiveByDapp()constant returns (uint allIncentive)
    {
        GD=governanceData(GDAddress);
        for(uint i=0; i<GD.getProposalLength(); i++)
        {
            allIncentive =  allIncentive + GD.getProposalIncentive(i);
        }
    }

    function getTotalStakeAgainstProposal(uint _proposalId)constant returns(uint totalStake)
    {
       GD=governanceData(GDAddress);

       uint Stake = getVoteStakeById(_proposalId) + getOptionStakeByProposalId(_proposalId);
       totalStake = GD.getProposalStake(_proposalId) + Stake;
    }

    function getVoteStakeById(uint _proposalId)constant returns (uint totalVoteStake)
    {
       GD=governanceData(GDAddress);

       uint length = GD.getVoteLengthById(_proposalId);
       for(uint i=0;i< length; i++ )
       {
          uint _voteId = GD.getVoteIdById(_proposalId,i);
          uint voterStake = GD.getVoteStake(_voteId);
          totalVoteStake = totalVoteStake + voterStake;
       }
    }

    function getOptionStakeByProposalId(uint _proposalId)constant returns(uint totalOptionStake)
    {
       GD=governanceData(GDAddress);
       uint8 totalOptions = GD.getTotalVerdictOptions(_proposalId);
       for(uint i =0; i< totalOptions; i++)
       {
          uint stake = GD.getOptionStakeById(_proposalId,i);
          totalOptionStake = totalOptionStake + stake;
        }
    }

    /// @dev Get the Value, stake and Address of the member whosoever added that verdict option.
    function getOptionDetailsById1(uint _proposalId,uint _optionIndex) constant returns(uint propId, uint optionid,uint optionStake,uint optionValue,address memberAddress,uint optionReward,uint dateAdded)
    {
        GD=governanceData(GDAddress);
        propId = _proposalId;
        optionid = _optionIndex;
        optionStake = GD.getOptionStakeById(_proposalId,_optionIndex);
        optionValue = GD.getOptionValueByProposalId(_proposalId,_optionIndex);
        memberAddress = GD.getOptionAddressByProposalId(_proposalId,_optionIndex);
        optionReward = GD.getOptionReward(_proposalId,_optionIndex);
        dateAdded = GD.getOptionDateAdded(_proposalId,_optionIndex);
        return (_proposalId,optionid,optionStake,optionValue,memberAddress,optionReward,dateAdded);
    } 

    function calculateProposalReward(address  _memberAddress,uint _createId,uint _proposalCreateLength) internal
    {
        GD=governanceData(GDAddress);
        uint lastIndex = 0; uint proposalId;uint category;uint finalVredict;uint proposalStatus;uint calcReward
        for(i=createId; i<proposalCreateLength; i++)
        {   
            (proposalId,category,finalVredict,proposalStatus) = GD.getProposalDetailsByAddress(_memberAddress,i);
            if(proposalStatus< 2)
                lastIndex = i;

            if(finalVredict > 0 && GD.getReturnedTokens(_memberAddress,proposalId,'P') == 0)
            {
                calcReward = (PC.getRewardPercProposal(category)*GD.getProposalTotalReward(proposalId))/100;
                finalRewardToDistribute = finalRewardToDistribute + calcReward + GD.getDepositedTokens(_memberAddress,_proposalId,'P');
                GD.callRewardEvent(_memberAddress,proposalId,"GBT Reward for being Proposal owner - Accepted ",calcReward)
                GD.setReturnedTokens(_memberAddress,proposalId,'P',1);
            }
        }

        if(lastIndex == 0)
          lastIndex = i;
        setProposalCreate(_memberAddress,lastIndex);
    }

    function calculateOptionReward(address _memberAddress,uint _optionId,uint _optionCreateLength) internal
    {
        GD=governanceData(GDAddress);
        uint lastIndex = 0;uint i;uint proposalId;uint optionId;uint proposalStatus;uint finalVredict;
        for(i=optionId; i<optionCreateLength; i++)
        {
            (proposalId,optionId,proposalStatus,finalVredict) = GD.getOptionIdAgainstProposalByAddress(_memberAddress,i);
            if(propStatus< 2)
                lastIndex = i;

            if(finalVredict> 0 && finalVredict == optionId && GD.getReturnedTokens(_memberAddress,proposalId,'S') == 0)
            {
                calcReward = (PC.getRewardPercOption(category)*GD.getProposalTotalReward(proposalId))/100;
                finalRewardToDistribute = finalRewardToDistribute + calcReward + GD.getDepositedTokens(_memberAddress,_proposalId,'S');
                GD.callRewardEvent(_memberAddress,_proposalId,"GBT Reward earned for being Solution owner - Final Solution by majority voting",calcReward);
                GD.setReturnedTokens(_memberAddress,proposalId,'S',1);
            }
        }

         if(lastIndex == 0)
          lastIndex = i;
        setOptionCreate(_memberAddress,lastIndex);
    }

    function calculateVoteReward(address _memberAddress,uint _voteId,uint _proposalVoteLength) internal
    {
        GD=governanceData(GDAddress);
        uint lastIndex = 0;uint i;uint proposalId;uint voteId;uint optionChosen;uint proposalStatus;uint finalVredict;
        for(i=voteId; i<proposalVoteLength; i++)
        {
            (voteId,proposalId,optionChosen,proposalStatus,finalVredict) = GD.getProposalDetailsByVoteId(_memberAddress,i,0);
            if(proposalStatus < 2)
                lastIndex = i;

            if(finalVredict > 0 && optionChosen == finalVredict && GD.getReturnedTokens(_memberAddress,proposalId,'V') == 0)
            {
                calcReward = (PC.getRewardPercVote(category)*GD.getProposalTotalReward(proposalId)*GD.getVoteValue(voteid))/(100*GD.getProposalReward(proposalId));
                finalRewardToDistribute = finalRewardToDistribute + calcReward + GD.getDepositedTokens(_memberAddress,_proposalId,'V');
                GD.callRewardEvent(_memberAddress,_proposalId,"GBT Reward earned for voting in favour of final option",calcReward);
                GD.setReturnedTokens(_memberAddress,proposalId,'V',1);
            }
        }
        if(lastIndex == 0)
          lastIndex = i;
        setProposalVote(_memberAddress,lastIndex);
    }


    function calculateMemberReward(address _memberAddress) constant returns(uint rewardToClaim)
    {
        uint createId;uint optionid;uint voteId; uint proposalCreateLength;uint optionCreateLength; uint proposalVoteLength;
        PC=ProposalCategory(PCAddress);
        GD=governanceData(GDAddress);
        GBTS=GBTStandardToken(GBTSAddress);
        (,proposalCreateLength,,optionCreateLength,,proposalVoteLength) = getMemberDetails(_memberAddress);
        (createId,optionId,voteId) = GD.getIdOfLastReward(_memberAddress);

        calculateProposalReward(_memberAddress,createId,proposalCreateLength);
        calculateOptionReward(_memberAddress,optionId,optionCreateLength);
        calculateVoteReward(_memberAddress,voteId,proposalVoteLength);
        return finalRewardToDistribute;
    }
}