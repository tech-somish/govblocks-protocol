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
import "./GovernanceData.sol";
import "./ProposalCategory.sol";
import "./MemberRoles.sol";
import "./Master.sol";
import "./BasicToken.sol";
import "./SafeMath.sol";
import "./Math.sol";
import "./Pool.sol";
import "./GBTController.sol";
import "./VotingType.sol";
import "./GovBlocksProxy.sol";
// import "./zeppelin-solidity/contracts/token/BasicToken.sol";
// import "./zeppelin-solidity/contracts/math/SafeMath.sol";
// import "./zeppelin-solidity/contracts/math/Math.sol";

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
  GBTController GBTC;
  Master MS;
  MemberRoles MR;
  ProposalCategory PC;
  GovernanceData GD;
  BasicToken BT;
  Pool P1;
  VotingType VT;

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

  function changeAllContractsAddress(address _GDContractAddress,address _MRContractAddress,address _PCContractAddress,address _PoolContractAddress) onlyInternal
  {
     GDAddress = _GDContractAddress;
     PCAddress = _PCContractAddress;
     MRAddress = _MRContractAddress;
     P1Address = _PoolContractAddress;
  }

  function changeGBTControllerAddress(address _GBTCAddress)
  {
     GBTCAddress = _GBTCAddress;
  }

  function changeMasterAddress(address _MasterAddress)
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
  
  /// @dev Transfer reward after Final Proposal Decision.
  function transferBackGBTtoken(address _memberAddress, uint _value) onlyInternal
  {
      GBTC=GBTController(GBTCAddress);
      GBTC.transferGBT(_memberAddress,_value);
  }

  function openProposalForVoting(uint _proposalId,uint _TokenAmount) public
  {
      PC = ProposalCategory(PCAddress);
      GD =GovernanceData(GDAddress);
      P1 = Pool(P1Address);

      require(GD.getProposalCategory(_proposalId) != 0 && GD.getProposalStatus(_proposalId) < 2);
      require(_TokenAmount >= PC.getMinStake(GD.getProposalCategory(_proposalId)) && _TokenAmount <= PC.getMaxStake(GD.getProposalCategory(_proposalId)));

      payableGBTTokens(_TokenAmount);
      setProposalValue(_proposalId,_TokenAmount);
      GD.changeProposalStatus(_proposalId,2);
      P1.closeProposalOraclise(_proposalId,PC.getClosingTimeByIndex(GD.getProposalCategory(_proposalId),0));
  }
  
 /// @dev Some amount to be paid while using GovBlocks contract service - Approve the contract to spend money on behalf of msg.sender
  function payableGBTTokens(uint _TokenAmount) 
  {
      GBTC=GBTController(GBTCAddress);
      GD=GovernanceData(GDAddress);
      require(_TokenAmount >= GD.GBTStakeValue());
      GBTC.receiveGBT(msg.sender,_TokenAmount);
  }

  /// @dev Edits a proposal and Only owner of a proposal can edit it.
  function editProposal(uint _proposalId ,string _proposalDescHash) onlyOwner public
  {
      GD=GovernanceData(GDAddress);
      GD.storeProposalVersion(_proposalId);
      updateProposalDetails1(_proposalId,_proposalDescHash);
      GD.changeProposalStatus(_proposalId,1);
      
      require(GD.getProposalCategory(_proposalId) > 0);
        GD.setProposalCategory(_proposalId,0);
  }

  /// @dev Calculate the proposal value to distribute it later - Distribute amount depends upon the final decision against proposal.
  function setProposalValue(uint _proposalId,uint _memberStake) internal
  {
      GD=GovernanceData(GDAddress);
      GD.setProposalStake(_proposalId,_memberStake);
      uint memberLevel = Math.max256(GD.getMemberReputation(msg.sender),1);
      uint tokensHeld = SafeMath.div((SafeMath.mul(SafeMath.mul(GD.getBalanceOfMember(msg.sender),100),100)),GD.getTotalTokenInSupply());
      uint maxValue= Math.max256(tokensHeld,GD.membershipScalingFactor());

      uint finalProposalValue = SafeMath.mul(SafeMath.mul(GD.globalRiskFactor(),memberLevel),SafeMath.mul(_memberStake,maxValue));
      GD.setProposalValue(_proposalId,finalProposalValue);
  }

  function setProposalCategoryParams(uint _category,uint _proposalId,uint[] _paramInt,bytes32[] _paramBytes32,address[] _paramAddress) onlyInternal
  {
      GD=GovernanceData(GDAddress);
      PC=ProposalCategory(PCAddress);
      setProposalCategoryParams1(_proposalId,_paramInt,_paramBytes32,_paramAddress);

      uint8 paramInt; uint8 paramBytes32; uint8 paramAddress;bytes32 parameterName; uint j;
      (,,,,paramInt,paramBytes32,paramAddress,,) = PC.getCategoryDetails(_category);
      
      for(j=0; j<paramInt; j++)
      {
          parameterName = PC.getCategoryParamNameUint(_category,j);
          GD.setParameterDetails1(_proposalId,parameterName,_paramInt[j]);
      }

      for(j=0; j<paramBytes32; j++)
      {
          parameterName = PC.getCategoryParamNameBytes(_category,j); 
          GD.setParameterDetails2(_proposalId,parameterName,_paramBytes32[j]);
      }

      for(j=0; j<paramAddress; j++)
      {
          parameterName = PC.getCategoryParamNameAddress(_category,j);
          GD.setParameterDetails3(_proposalId,parameterName,_paramAddress[j]); 
      }
  }

  /// @dev categorizing proposal to proceed further.
  function categorizeProposal(uint _proposalId , uint8 _categoryId,uint8 _proposalComplexityLevel,uint _reward) public
  {
      MR = MemberRoles(MRAddress);
      GD = GovernanceData(GDAddress);

      require(MR.getMemberRoleIdByAddress(msg.sender) == MR.getAuthorizedMemberId());
      require(GD.getProposalStatus(_proposalId) == 1 || GD.getProposalStatus(_proposalId) == 0);

      addComplexityLevelAndReward(_proposalId,_categoryId,_proposalComplexityLevel,_reward);
      addInitialOptionDetails(_proposalId,msg.sender);
      GD.setCategorizedBy(_proposalId,msg.sender);
      GD.setProposalCategory(_proposalId,_categoryId);
  }

  /// @dev Proposal's complexity level and reward is added 
  function addComplexityLevelAndReward(uint _proposalId,uint _category,uint8 _proposalComplexityLevel,uint _reward) internal
  {
      GD=GovernanceData(GDAddress);
      GD.setProposalLevel(_proposalId,_proposalComplexityLevel);
      GD.setProposalIncentive(_proposalId,_reward); 
  }

 /// @dev Creates a new proposal.
  function createProposal(string _proposalDescHash,uint _votingTypeId,uint8 _categoryId,uint _TokenAmount) public
  {
      GD=GovernanceData(GDAddress);
      PC=ProposalCategory(PCAddress);
      require(GD.getBalanceOfMember(msg.sender) != 0);

      GD.setMemberReputation("CreateProposal",GD.getProposalLength(),msg.sender,1);
      GD.addTotalProposal(GD.getProposalLength(),msg.sender);

      if(_categoryId > 0)
      {
          uint _proposalId = GD.getProposalLength();
          GD.addNewProposal(msg.sender,_proposalDescHash,_categoryId,GD.getVotingTypeAddress(_votingTypeId));
          openProposalForVoting(_proposalId,_TokenAmount);
          addInitialOptionDetails(_proposalId,msg.sender);
          GD.setCategorizedBy(_proposalId,msg.sender);
          uint incentive;
          (,incentive) = PC.getCategoryIncentive(_categoryId);
          GD.setProposalIncentive(_proposalId,incentive); 
      }
      else
          GD.addNewProposal(msg.sender,_proposalDescHash,_categoryId,GD.getVotingTypeAddress(_votingTypeId));          
  }
  
 /// @dev Creates a new proposal.
  function createProposalwithOption(string _proposalDescHash,uint _votingTypeId,uint8 _categoryId,uint _TokenAmount,uint[] _paramInt,bytes32[] _paramBytes32,address[] _paramAddress,string _optionDescHash) public
  {
      GD=GovernanceData(GDAddress);

      require(GD.getBalanceOfMember(msg.sender) != 0);
      require(_categoryId != 0);
      GD.setMemberReputation("createProposalwithOption",GD.getProposalLength(),msg.sender,1);
      
      GD.addTotalProposal(GD.getProposalLength(),msg.sender);
      uint _proposalId = GD.getProposalLength();
      GD.addNewProposal(msg.sender,_proposalDescHash,_categoryId,GD.getVotingTypeAddress(_votingTypeId));
      openProposalForVoting(_proposalId,_TokenAmount/2);
      addInitialOptionDetails(_proposalId,msg.sender);
      GD.setCategorizedBy(_proposalId,msg.sender);
      VT=VotingType(GD.getVotingTypeAddress(_votingTypeId));
      VT.addVerdictOption(_proposalId,msg.sender,_paramInt,_paramBytes32,_paramAddress,_TokenAmount,_optionDescHash);
  }
  /// @dev AFter the proposal final decision, member reputation will get updated.
  function updateMemberReputation(uint _proposalId,uint _finalVerdict) onlyInternal
  {
    GD=GovernanceData(GDAddress);
    address _proposalOwner =  GD.getProposalOwner(_proposalId);
    address _finalOptionOwner = GD.getOptionAddressByProposalId(_proposalId,_finalVerdict);
    uint addProposalOwnerPoints; uint addOptionOwnerPoints; uint subProposalOwnerPoints; uint subOptionOwnerPoints;
    (addProposalOwnerPoints,addOptionOwnerPoints,,subProposalOwnerPoints,subOptionOwnerPoints,)= GD.getMemberReputationPoints();

    if(_finalVerdict>0)
    {
        GD.setMemberReputation("ProposalOwner Accepted",_proposalId,_proposalOwner,SafeMath.add(GD.getMemberReputation(_proposalOwner),addProposalOwnerPoints));
        GD.setMemberReputation("OptionOwner Favour",_proposalId,_finalOptionOwner,SafeMath.add(GD.getMemberReputation(_finalOptionOwner),addOptionOwnerPoints)); 
    }
    else
    {
        GD.setMemberReputation("ProposalOwner Rejected",_proposalId,_proposalOwner,SafeMath.sub(GD.getMemberReputation(_proposalOwner),subProposalOwnerPoints));
        for(uint i=0; i<GD.getOptionAddedAddressLength(_proposalId); i++)
        {
            address memberAddress = GD.getOptionAddressByProposalId(_proposalId,i);
            GD.setMemberReputation("OptionOwner Against",_proposalId,memberAddress,SafeMath.sub(GD.getMemberReputation(memberAddress),subOptionOwnerPoints));
        }
    }   
  }

  /// @dev Afer proposal Final Decision, Member reputation will get updated.
  function updateMemberReputation1(string _desc,uint _proposalId,address _voterAddress,uint _voterPoints) onlyInternal
  {
     GD=GovernanceData(GDAddress);
     GD.setMemberReputation(_desc,_proposalId,_voterAddress,_voterPoints);
  }

  function checkProposalVoteClosing(uint _proposalId) onlyInternal constant returns(uint8 closeValue) 
  {
      PC=ProposalCategory(PCAddress);
      GD=GovernanceData(GDAddress);
      MR=MemberRoles(MRAddress);
      
      uint currentVotingId;uint category;
      (,category,currentVotingId,,,) = GD.getProposalDetailsById2(_proposalId);
      uint dateUpdate;
      (,,,,dateUpdate,,) = GD.getProposalDetailsById1(_proposalId);
      address votingTypeAddress;
      (,,,,,votingTypeAddress) = GD.getProposalDetailsById2(_proposalId);
      VT=VotingType(votingTypeAddress);
      uint roleId = PC.getRoleSequencAtIndex(category,currentVotingId);

      if(SafeMath.add(dateUpdate,PC.getClosingTimeByIndex(category,currentVotingId)) <= now || GD.getVoteLength(_proposalId,roleId) == MR.getAllMemberLength(roleId))
        closeValue=1;
  }

 function checkRoleVoteClosing(uint _proposalId,uint _roleVoteLength) 
  {
     PC=ProposalCategory(PCAddress);
     GD=GovernanceData(GDAddress);
     MR=MemberRoles(MRAddress);
     P1=Pool(P1Address);

      uint currentVotingId;uint category;
      (,category,currentVotingId,,,) = GD.getProposalDetailsById2(_proposalId);
      
      uint roleId = PC.getRoleSequencAtIndex(category,currentVotingId);
      if(_roleVoteLength == MR.getAllMemberLength(roleId))
        P1.closeProposalOraclise1(_proposalId);
  }
  
    function getStatusOfProposalsForMember(uint[] _proposalsIds)constant returns (uint proposalLength,uint draftProposals,uint pendingProposals,uint acceptedProposals,uint rejectedProposals)
    {
         GD=GovernanceData(GDAddress);
         uint proposalStatus;

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
    GD=GovernanceData(GDAddress);
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
        GD=GovernanceData(GDAddress);
        require(GD.getVoterAddress(_voteId) == _memberAddress);
          (,proposalId,,dateAdded,,voteStake,) = GD.getVoteDetailByid(_voteId);
          voteReward = GD.getVoteReward(_voteId); 
    } 

    function getProposalOptionAllById(uint _proposalId,uint _optionIndex)constant returns(uint proposalId,uint[] intParam,bytes32[] bytesParam,address[] addressParam)
    {
        
        PC=ProposalCategory(PCAddress);
        GD=GovernanceData(GDAddress);
        proposalId = _proposalId;

        uint8 paramInt; uint8 paramBytes32; uint8 paramAddress;bytes32 parameterName; uint j;
        (,,,,paramInt,paramBytes32,paramAddress,,) = PC.getCategoryDetails(GD.getProposalCategory(_proposalId));
        
        intParam=new uint[](paramInt);
        bytesParam = new bytes32[](paramBytes32);
        addressParam = new address[](paramAddress);

        for(j=0; j<paramInt; j++)
        {
            parameterName = PC.getCategoryParamNameUint(GD.getProposalCategory(_proposalId),j);
            intParam[j] = GD.getParameterDetailsById1(_proposalId,parameterName,_optionIndex);
        }

        for(j=0; j<paramBytes32; j++)
        {
            parameterName = PC.getCategoryParamNameBytes(GD.getProposalCategory(_proposalId),j); 
            bytesParam[j] = GD.getParameterDetailsById2(_proposalId,parameterName,_optionIndex);
        }

        for(j=0; j<paramAddress; j++)
        {
            parameterName = PC.getCategoryParamNameAddress(GD.getProposalCategory(_proposalId),j);
            addressParam[j] = GD.getParameterDetailsById3(_proposalId,parameterName,_optionIndex);              
        }  
    }

    /// @dev Get the Value, stake and Address of the member whosoever added that verdict option.
    function getOptionDetailsById(uint _proposalId,uint _optionIndex) constant returns(uint id, uint optionid,uint optionStake,uint optionValue,address memberAddress,uint optionReward)
    {
        GD=GovernanceData(GDAddress);

        id = _proposalId;
        optionid = _optionIndex;
        optionStake = GD.getOptionStakeById(_proposalId,_optionIndex);
        optionValue = GD.getOptionValueByProposalId(_proposalId,_optionIndex);
        memberAddress = GD.getOptionAddressByProposalId(_proposalId,_optionIndex);
        optionReward = GD.getOptionReward(_proposalId,_optionIndex);
        return (_proposalId,optionid,optionStake,optionValue,memberAddress,optionReward);
    }

    function getOptionDetailsByAddress(uint _proposalId,address _memberAddress) constant returns(uint id,uint optionStake,uint optionReward,uint dateAdded,uint proposalId)
    {
        GD=GovernanceData(GDAddress);

        id = _optionIndex;
        uint _optionIndex = GD.getOptionIdByAddress(_proposalId,_memberAddress);
        optionStake = GD.getOptionStakeById(_proposalId,_optionIndex);
        optionReward = GD.getOptionReward(_proposalId,_optionIndex);
        dateAdded = GD.getOptionDateAdded(_proposalId,_optionIndex);
        proposalId = _proposalId;    
    }

    function getProposalRewardByMember(address _memberAddress) constant returns(uint[] propStake,uint[] propReward)
    {
        propStake = new uint[](GD.getTotalProposal(_memberAddress));
        propReward = new uint[](GD.getTotalProposal(_memberAddress));

        for(uint i=0; i<GD.getTotalProposal(_memberAddress); i++)
        {
            propStake[i] = GD.getProposalStake(GD.getProposalIdByAddress(_memberAddress,i));
            propReward[i] = GD.getProposalReward(GD.getProposalIdByAddress(_memberAddress,i));
        }
    }

    function setProposalCategoryParams1(uint _proposalId,uint[] _paramInt,bytes32[] _paramBytes32,address[] _paramAddress) internal
    {
        GD=GovernanceData(GDAddress);
        uint i;
        GD.setTotalOptions(_proposalId);

        for(i=0;i<_paramInt.length;i++)
        {
            GD.setOptionIntParameter(_proposalId,_paramInt[i]);
        }

        for(i=0;i<_paramBytes32.length;i++)
        {
            GD.setOptionBytesParameter(_proposalId,_paramBytes32[i]);
        }

        for(i=0;i<_paramAddress.length;i++)
        {
            GD.setOptionAddressParameter(_proposalId,_paramAddress[i]); 
        }   
    }

    function getProposalStakeByMember(address _memberAddress) returns(uint stakeValueProposal)
    {
        for(uint i=0; i<GD.getTotalProposal(_memberAddress); i++)
        {
            stakeValueProposal = stakeValueProposal + GD.getProposalStake(GD.getProposalIdByAddress(_memberAddress,i));
        }
    }

    function getOptionStakeByMember(address _memberAddress)constant returns(uint stakeValueOption)
    {
        for(uint i=0; i<GD.getProposalAnsLength(_memberAddress); i++)
        {
            stakeValueOption = stakeValueOption + GD.getOptionStakeById(i,GD.getOptionIdByAddress(i,_memberAddress));
        }
    }

    function setProposalDetails(uint _proposalId,uint _totaltoken,uint _blockNumber,uint _reward)
    {
       GD=GovernanceData(GDAddress);
       GD.setProposalTotalToken(_proposalId,_totaltoken);
       GD.setProposalBlockNo(_proposalId,_blockNumber);
       GD.steProposalReward(_proposalId,_reward);
    }

    function getMemberDetails(address _memberAddress) constant returns(uint memberReputation, uint totalProposal,uint proposalStake,uint totalOption,uint optionStake,uint totalVotes)
    {
        GD=GovernanceData(GDAddress);
        memberReputation = GD.getMemberReputation(_memberAddress);
        totalProposal = GD.getTotalProposal(_memberAddress);
        proposalStake = getProposalStakeByMember(_memberAddress);
        totalOption = GD.getProposalAnsLength(_memberAddress);
        optionStake = getOptionStakeByMember(_memberAddress);
        totalVotes = GD.getTotalVotesByAddress(_memberAddress);
    }

    /// @dev As bydefault first option is alwayd deny option. One time configurable.
    function addInitialOptionDetails(uint _proposalId,address _memberAddress) internal
    {
        GD=GovernanceData(GDAddress);
        if(GD.getInitialOptionsAdded(_proposalId) == 0)
        {
            GD.setOptionAddress(_proposalId,_memberAddress);
            GD.setOptionStake(_proposalId,0);
            GD.setOptionValue(_proposalId,0);
            GD.setOptionDesc(_proposalId,"");
            GD.setOptionDateAdded(_proposalId);
            GD.setTotalOptions(_proposalId);
            GD.setOptionIntParameter(_proposalId,0);
            GD.setOptionBytesParameter(_proposalId,"");
            GD.setOptionAddressParameter(_proposalId,0x00);
            GD.setInitialOptionsAdded(_proposalId);
        }
    }

    /// @dev Change pending proposal start variable
    function changePendingProposalStart() onlyInternal
    {
        GD=GovernanceData(GDAddress);
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
        GD=GovernanceData(GDAddress);
        GD.setProposalCurrentVotingId(_proposalId,_currVotingStatus);
        GD.setProposalIntermediateVerdict(_proposalId,_intermediateVerdict);
        GD.setProposalFinalVerdict(_proposalId,_finalVerdict);
    }

    /// @dev Edits the details of an existing proposal and creates new version.
    function updateProposalDetails1(uint _proposalId,string _proposalDescHash) internal
    {
        GD=GovernanceData(GDAddress);
        GD.setProposalDesc(_proposalId,_proposalDescHash);
        GD.setProposalDateUpd(_proposalId);
        GD.setProposalVersion(_proposalId);
    }

}