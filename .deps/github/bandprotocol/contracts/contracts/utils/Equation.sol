pragma solidity 0.5.9;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../../bancor/BancorPower.sol";


library Equation {
  using SafeMath for uint256;

  /// An expression tree is encoded as a set of nodes, with root node having index zero. Each node has 3 values:
  ///  1. opcode: the expression that the node represents. See table below.
  /// +--------+----------------------------------------+------+------------+
  /// | Opcode |              Description               | i.e. | # children |
  /// +--------+----------------------------------------+------+------------+
  /// |   00   | Integer Constant                       |   c  |      0     |
  /// |   01   | Variable                               |   X  |      0     |
  /// |   02   | Arithmetic Square Root                 |   √  |      1     |
  /// |   03   | Boolean Not Condition                  |   !  |      1     |
  /// |   04   | Arithmetic Addition                    |   +  |      2     |
  /// |   05   | Arithmetic Subtraction                 |   -  |      2     |
  /// |   06   | Arithmetic Multiplication              |   *  |      2     |
  /// |   07   | Arithmetic Division                    |   /  |      2     |
  /// |   08   | Arithmetic Exponentiation              |  **  |      2     |
  /// |   09   | Arithmetic Percentage* (see below)     |   %  |      2     |
  /// |   10   | Arithmetic Equal Comparison            |  ==  |      2     |
  /// |   11   | Arithmetic Non-Equal Comparison        |  !=  |      2     |
  /// |   12   | Arithmetic Less-Than Comparison        |  <   |      2     |
  /// |   13   | Arithmetic Greater-Than Comparison     |  >   |      2     |
  /// |   14   | Arithmetic Non-Greater-Than Comparison |  <=  |      2     |
  /// |   15   | Arithmetic Non-Less-Than Comparison    |  >=  |      2     |
  /// |   16   | Boolean And Condition                  |  &&  |      2     |
  /// |   17   | Boolean Or Condition                   |  ||  |      2     |
  /// |   18   | Ternary Operation                      |  ?:  |      3     |
  /// |   19   | Bancor's log** (see below)             |      |      3     |
  /// |   20   | Bancor's power*** (see below)          |      |      4     |
  /// +--------+----------------------------------------+------+------------+
  ///  2. children: the list of node indices of this node's sub-expressions. Different opcode nodes will have different
  ///     number of children.
  ///  3. value: the value inside the node. Currently this is only relevant for Integer Constant (Opcode 00).
  /// (*) Arithmetic percentage is computed by multiplying the left-hand side value with the right-hand side,
  ///     and divide the result by 10^18, rounded down to uint256 integer.
  /// (**) Using BancorFormula, the opcode computes log of fractional numbers. However, this fraction's value must
  ///     be more than 1. (baseN / baseD >= 1). The opcode takes 3 childrens(c, baseN, baseD), and computes
  ///     (c * log(baseN / baseD)) limitation is in range of 1 <= baseN / baseD <= 58774717541114375398436826861112283890
  ///     (= 1e76/FIXED_1), where FIXED_1 defined in BancorPower.sol
  /// (***) Using BancorFomula, the opcode computes exponential of fractional numbers. The opcode takes 4 children
  ///     (c,baseN,baseD,expV), and computes (c * ((baseN / baseD) ^ (expV / 1e6))). See implementation for the
  ///     limitation of the each value's domain. The end result must be in uint256 range.
  struct Node {
    uint8 opcode;
    uint8 child0;
    uint8 child1;
    uint8 child2;
    uint8 child3;
    uint256 value;
  }

  enum ExprType { Invalid, Math, Boolean }

  uint8 constant OPCODE_CONST = 0;
  uint8 constant OPCODE_VAR = 1;
  uint8 constant OPCODE_SQRT = 2;
  uint8 constant OPCODE_NOT = 3;
  uint8 constant OPCODE_ADD = 4;
  uint8 constant OPCODE_SUB = 5;
  uint8 constant OPCODE_MUL = 6;
  uint8 constant OPCODE_DIV = 7;
  uint8 constant OPCODE_EXP = 8;
  uint8 constant OPCODE_PCT = 9;
  uint8 constant OPCODE_EQ = 10;
  uint8 constant OPCODE_NE = 11;
  uint8 constant OPCODE_LT = 12;
  uint8 constant OPCODE_GT = 13;
  uint8 constant OPCODE_LE = 14;
  uint8 constant OPCODE_GE = 15;
  uint8 constant OPCODE_AND = 16;
  uint8 constant OPCODE_OR = 17;
  uint8 constant OPCODE_IF = 18;
  uint8 constant OPCODE_BANCOR_LOG = 19;
  uint8 constant OPCODE_BANCOR_POWER = 20;
  uint8 constant OPCODE_INVALID = 21;

  /// @dev Initialize equation by array of opcodes/values in prefix order. Array
  /// is read as if it is the *pre-order* traversal of the expression tree.
  function init(Node[] storage self, uint256[] calldata _expressions) external {
    /// Init should only be called when the equation is not yet initialized.
    require(self.length == 0);
    /// Limit expression length to < 256 to make sure gas cost is managable.
    require(_expressions.length < 256);
    for (uint8 idx = 0; idx < _expressions.length; ++idx) {
      uint256 opcode = _expressions[idx];
      require(opcode < OPCODE_INVALID);
      Node memory node;
      node.opcode = uint8(opcode);
      /// Get the node's value. Only applicable on Integer Constant case.
      if (opcode == OPCODE_CONST) {
        node.value = _expressions[++idx];
      }
      self.push(node);
    }
    (uint8 lastNodeIndex,) = populateTree(self, 0);
    require(lastNodeIndex == self.length - 1);
  }

  /// Calculate the Y position from the X position for this equation.
  function calculate(Node[] storage self, uint256 xValue) external view returns (uint256) {
    return solveMath(self, 0, xValue);
  }

  /// Return the number of children the given opcode node has.
  function getChildrenCount(uint8 opcode) private pure returns (uint8) {
    if (opcode <= OPCODE_VAR) {
      return 0;
    } else if (opcode <= OPCODE_NOT) {
      return 1;
    } else if (opcode <= OPCODE_OR) {
      return 2;
    } else if (opcode <= OPCODE_BANCOR_LOG) {
      return 3;
    } else if (opcode <= OPCODE_BANCOR_POWER) {
      return 4;
    }
    revert();
  }

  /// Check whether the given opcode and list of expression types match. Revert on failure.
  function checkExprType(uint8 opcode, ExprType[] memory types)
    private pure returns (ExprType)
  {
    if (opcode <= OPCODE_VAR) {
      return ExprType.Math;
    } else if (opcode == OPCODE_SQRT) {
      require(types[0] == ExprType.Math);
      return ExprType.Math;
    } else if (opcode == OPCODE_NOT) {
      require(types[0] == ExprType.Boolean);
      return ExprType.Boolean;
    } else if (opcode >= OPCODE_ADD && opcode <= OPCODE_PCT) {
      require(types[0] == ExprType.Math);
      require(types[1] == ExprType.Math);
      return ExprType.Math;
    } else if (opcode >= OPCODE_EQ && opcode <= OPCODE_GE) {
      require(types[0] == ExprType.Math);
      require(types[1] == ExprType.Math);
      return ExprType.Boolean;
    } else if (opcode >= OPCODE_AND && opcode <= OPCODE_OR) {
      require(types[0] == ExprType.Boolean);
      require(types[1] == ExprType.Boolean);
      return ExprType.Boolean;
    } else if (opcode == OPCODE_IF) {
      require(types[0] == ExprType.Boolean);
      require(types[1] != ExprType.Invalid);
      require(types[1] == types[2]);
      return types[1];
    } else if (opcode == OPCODE_BANCOR_LOG) {
      require(types[0] == ExprType.Math);
      require(types[1] == ExprType.Math);
      require(types[2] == ExprType.Math);
      return ExprType.Math;
    } else if (opcode == OPCODE_BANCOR_POWER) {
      require(types[0] == ExprType.Math);
      require(types[1] == ExprType.Math);
      require(types[2] == ExprType.Math);
      require(types[3] == ExprType.Math);
      return ExprType.Math;
    }
    revert();
  }

  /// Helper function to recursively populate node infoMaprmation following the given pre-order
  /// node list. It inspects the opcode and recursively call populateTree(s) accordingly.
  /// @param self storage pointer to equation data to build tree.
  /// @param currentNodeIndex the index of the current node to populate infoMap.
  /// @return An (uint8, bool). The first value represents the last  (highest/rightmost) node
  /// index of the current subtree. The second value indicates the type of this subtree.
  function populateTree(Node[] storage self, uint8 currentNodeIndex)
    private returns (uint8, ExprType)
  {
    require(currentNodeIndex < self.length);
    Node storage node = self[currentNodeIndex];
    uint8 opcode = node.opcode;
    uint8 childrenCount = getChildrenCount(opcode);
    ExprType[] memory childrenTypes = new ExprType[](childrenCount);
    uint8 lastNodeIdx = currentNodeIndex;
    for (uint8 idx = 0; idx < childrenCount; ++idx) {
      if (idx == 0) node.child0 = lastNodeIdx + 1;
      else if (idx == 1) node.child1 = lastNodeIdx + 1;
      else if (idx == 2) node.child2 = lastNodeIdx + 1;
      else if (idx == 3) node.child3 = lastNodeIdx + 1;
      else revert();
      (lastNodeIdx, childrenTypes[idx]) = populateTree(self, lastNodeIdx + 1);
    }
    ExprType exprType = checkExprType(opcode, childrenTypes);
    return (lastNodeIdx, exprType);
  }


  function solveMath(Node[] storage self, uint8 nodeIdx, uint256 xValue)
    private view returns (uint256)
  {
    Node storage node = self[nodeIdx];
    uint8 opcode = node.opcode;
    if (opcode == OPCODE_CONST) {
      return node.value;
    } else if (opcode == OPCODE_VAR) {
      return xValue;
    } else if (opcode == OPCODE_SQRT) {
      uint256 childValue = solveMath(self, node.child0, xValue);
      uint256 temp = childValue.add(1).div(2);
      uint256 result = childValue;
      while (temp < result) {
        result = temp;
        temp = childValue.div(temp).add(temp).div(2);
      }
      return result;
    } else if (opcode >= OPCODE_ADD && opcode <= OPCODE_PCT) {
      uint256 leftValue = solveMath(self, node.child0, xValue);
      uint256 rightValue = solveMath(self, node.child1, xValue);
      if (opcode == OPCODE_ADD) {
        return leftValue.add(rightValue);
      } else if (opcode == OPCODE_SUB) {
        return leftValue.sub(rightValue);
      } else if (opcode == OPCODE_MUL) {
        return leftValue.mul(rightValue);
      } else if (opcode == OPCODE_DIV) {
        return leftValue.div(rightValue);
      } else if (opcode == OPCODE_EXP) {
        uint256 power = rightValue;
        uint256 expResult = 1;
        for (uint256 idx = 0; idx < power; ++idx) {
          expResult = expResult.mul(leftValue);
        }
        return expResult;
      } else if (opcode == OPCODE_PCT) {
        return leftValue.mul(rightValue).div(1e18);
      }
    } else if (opcode == OPCODE_IF) {
      bool condValue = solveBool(self, node.child0, xValue);
      if (condValue) return solveMath(self, node.child1, xValue);
      else return solveMath(self, node.child2, xValue);
    } else if (opcode == OPCODE_BANCOR_LOG) {
      uint256 multiplier = solveMath(self, node.child0, xValue);
      uint256 baseN = solveMath(self, node.child1, xValue);
      uint256 baseD = solveMath(self, node.child2, xValue);
      return BancorPower.log(multiplier, baseN, baseD);
    } else if (opcode == OPCODE_BANCOR_POWER) {
      uint256 multiplier = solveMath(self, node.child0, xValue);
      uint256 baseN = solveMath(self, node.child1, xValue);
      uint256 baseD = solveMath(self, node.child2, xValue);
      uint256 expV = solveMath(self, node.child3, xValue);
      require(expV < 1 << 32);
      (uint256 expResult, uint8 precision) = BancorPower.power(baseN, baseD, uint32(expV), 1e6);
      return expResult.mul(multiplier) >> precision;
    }
    revert();
  }

  function solveBool(Node[] storage self, uint8 nodeIdx, uint256 xValue)
    private view returns (bool)
  {
    Node storage node = self[nodeIdx];
    uint8 opcode = node.opcode;
    if (opcode == OPCODE_NOT) {
      return !solveBool(self, node.child0, xValue);
    } else if (opcode >= OPCODE_EQ && opcode <= OPCODE_GE) {
      uint256 leftValue = solveMath(self, node.child0, xValue);
      uint256 rightValue = solveMath(self, node.child1, xValue);
      if (opcode == OPCODE_EQ) {
        return leftValue == rightValue;
      } else if (opcode == OPCODE_NE) {
        return leftValue != rightValue;
      } else if (opcode == OPCODE_LT) {
        return leftValue < rightValue;
      } else if (opcode == OPCODE_GT) {
        return leftValue > rightValue;
      } else if (opcode == OPCODE_LE) {
        return leftValue <= rightValue;
      } else if (opcode == OPCODE_GE) {
        return leftValue >= rightValue;
      }
    } else if (opcode >= OPCODE_AND && opcode <= OPCODE_OR) {
      bool leftBoolValue = solveBool(self, node.child0, xValue);
      if (opcode == OPCODE_AND) {
        if (leftBoolValue) return solveBool(self, node.child1, xValue);
        else return false;
      } else if (opcode == OPCODE_OR) {
        if (leftBoolValue) return true;
        else return solveBool(self, node.child1, xValue);
      }
    } else if (opcode == OPCODE_IF) {
      bool condValue = solveBool(self, node.child0, xValue);
      if (condValue) return solveBool(self, node.child1, xValue);
      else return solveBool(self, node.child2, xValue);
    }
    revert();
  }
}
