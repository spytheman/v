module matching

[direct_array_access]
pub fn token_by_keyword(word string) int {
	wlen := word.len
	if wlen < 2 || wlen > 10 {
		return -1
	}
	mut cptr := unsafe { word.str }
	match wlen {
		2 {
			if *cptr == 97 { // `a`
				unsafe { cptr++ }
				if *cptr == 115 { // `s`
					return 67 // as
				}
				return -1
			}
			if *cptr == 102 { // `f`
				unsafe { cptr++ }
				if *cptr == 110 { // `n`
					return 79 // fn
				}
				return -1
			}
			if *cptr == 103 { // `g`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					return 81 // go
				}
				return -1
			}
			if *cptr == 105 { // `i`
				unsafe { cptr++ }
				if *cptr == 102 { // `f`
					return 83 // if
				}
				if *cptr == 110 { // `n`
					return 85 // in
				}
				if *cptr == 115 { // `s`
					return 87 // is
				}
				return -1
			}
			if *cptr == 111 { // `o`
				unsafe { cptr++ }
				if *cptr == 114 { // `r`
					return 108 // or
				}
				return -1
			}
		}
		3 {
			if *cptr == 97 { // `a`
				unsafe { cptr++ }
				if *cptr == 115 { // `s`
					unsafe { cptr++ }
					if *cptr == 109 { // `m`
						return 68 // asm
					}
					return -1
				}
				return -1
			}
			if *cptr == 102 { // `f`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 114 { // `r`
						return 78 // for
					}
					return -1
				}
				return -1
			}
			if *cptr == 109 { // `m`
				unsafe { cptr++ }
				if *cptr == 117 { // `u`
					unsafe { cptr++ }
					if *cptr == 116 { // `t`
						return 90 // mut
					}
					return -1
				}
				return -1
			}
			if *cptr == 110 { // `n`
				unsafe { cptr++ }
				if *cptr == 105 { // `i`
					unsafe { cptr++ }
					if *cptr == 108 { // `l`
						return 91 // nil
					}
					return -1
				}
				return -1
			}
			if *cptr == 112 { // `p`
				unsafe { cptr++ }
				if *cptr == 117 { // `u`
					unsafe { cptr++ }
					if *cptr == 98 { // `b`
						return 110 // pub
					}
					return -1
				}
				return -1
			}
		}
		4 {
			if *cptr == 100 { // `d`
				unsafe { cptr++ }
				if *cptr == 117 { // `u`
					unsafe { cptr++ }
					if *cptr == 109 { // `m`
						unsafe { cptr++ }
						if *cptr == 112 { // `p`
							return 107 // dump
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 101 { // `e`
				unsafe { cptr++ }
				if *cptr == 108 { // `l`
					unsafe { cptr++ }
					if *cptr == 115 { // `s`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							return 75 // else
						}
						return -1
					}
					return -1
				}
				if *cptr == 110 { // `n`
					unsafe { cptr++ }
					if *cptr == 117 { // `u`
						unsafe { cptr++ }
						if *cptr == 109 { // `m`
							return 76 // enum
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 103 { // `g`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 116 { // `t`
						unsafe { cptr++ }
						if *cptr == 111 { // `o`
							return 82 // goto
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 108 { // `l`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 99 { // `c`
						unsafe { cptr++ }
						if *cptr == 107 { // `k`
							return 93 // lock
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 110 { // `n`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 110 { // `n`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							return 95 // none
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 116 { // `t`
				unsafe { cptr++ }
				if *cptr == 114 { // `r`
					unsafe { cptr++ }
					if *cptr == 117 { // `u`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							return 104 // true
						}
						return -1
					}
					return -1
				}
				if *cptr == 121 { // `y`
					unsafe { cptr++ }
					if *cptr == 112 { // `p`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							return 105 // type
						}
						return -1
					}
					return -1
				}
				return -1
			}
		}
		5 {
			if *cptr == 98 { // `b`
				unsafe { cptr++ }
				if *cptr == 114 { // `r`
					unsafe { cptr++ }
					if *cptr == 101 { // `e`
						unsafe { cptr++ }
						if *cptr == 97 { // `a`
							unsafe { cptr++ }
							if *cptr == 107 { // `k`
								return 71 // break
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 99 { // `c`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 110 { // `n`
						unsafe { cptr++ }
						if *cptr == 115 { // `s`
							unsafe { cptr++ }
							if *cptr == 116 { // `t`
								return 72 // const
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 100 { // `d`
				unsafe { cptr++ }
				if *cptr == 101 { // `e`
					unsafe { cptr++ }
					if *cptr == 102 { // `f`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 114 { // `r`
								return 74 // defer
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 102 { // `f`
				unsafe { cptr++ }
				if *cptr == 97 { // `a`
					unsafe { cptr++ }
					if *cptr == 108 { // `l`
						unsafe { cptr++ }
						if *cptr == 115 { // `s`
							unsafe { cptr++ }
							if *cptr == 101 { // `e`
								return 77 // false
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 109 { // `m`
				unsafe { cptr++ }
				if *cptr == 97 { // `a`
					unsafe { cptr++ }
					if *cptr == 116 { // `t`
						unsafe { cptr++ }
						if *cptr == 99 { // `c`
							unsafe { cptr++ }
							if *cptr == 104 { // `h`
								return 88 // match
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 114 { // `r`
				unsafe { cptr++ }
				if *cptr == 108 { // `l`
					unsafe { cptr++ }
					if *cptr == 111 { // `o`
						unsafe { cptr++ }
						if *cptr == 99 { // `c`
							unsafe { cptr++ }
							if *cptr == 107 { // `k`
								return 94 // rlock
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 117 { // `u`
				unsafe { cptr++ }
				if *cptr == 110 { // `n`
					unsafe { cptr++ }
					if *cptr == 105 { // `i`
						unsafe { cptr++ }
						if *cptr == 111 { // `o`
							unsafe { cptr++ }
							if *cptr == 110 { // `n`
								return 109 // union
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
		}
		6 {
			if *cptr == 97 { // `a`
				unsafe { cptr++ }
				if *cptr == 115 { // `s`
					unsafe { cptr++ }
					if *cptr == 115 { // `s`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 114 { // `r`
								unsafe { cptr++ }
								if *cptr == 116 { // `t`
									return 69 // assert
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 116 { // `t`
					unsafe { cptr++ }
					if *cptr == 111 { // `o`
						unsafe { cptr++ }
						if *cptr == 109 { // `m`
							unsafe { cptr++ }
							if *cptr == 105 { // `i`
								unsafe { cptr++ }
								if *cptr == 99 { // `c`
									return 70 // atomic
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 105 { // `i`
				unsafe { cptr++ }
				if *cptr == 109 { // `m`
					unsafe { cptr++ }
					if *cptr == 112 { // `p`
						unsafe { cptr++ }
						if *cptr == 111 { // `o`
							unsafe { cptr++ }
							if *cptr == 114 { // `r`
								unsafe { cptr++ }
								if *cptr == 116 { // `t`
									return 84 // import
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 109 { // `m`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 100 { // `d`
						unsafe { cptr++ }
						if *cptr == 117 { // `u`
							unsafe { cptr++ }
							if *cptr == 108 { // `l`
								unsafe { cptr++ }
								if *cptr == 101 { // `e`
									return 89 // module
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 114 { // `r`
				unsafe { cptr++ }
				if *cptr == 101 { // `e`
					unsafe { cptr++ }
					if *cptr == 116 { // `t`
						unsafe { cptr++ }
						if *cptr == 117 { // `u`
							unsafe { cptr++ }
							if *cptr == 114 { // `r`
								unsafe { cptr++ }
								if *cptr == 110 { // `n`
									return 96 // return
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 115 { // `s`
				unsafe { cptr++ }
				if *cptr == 101 { // `e`
					unsafe { cptr++ }
					if *cptr == 108 { // `l`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 99 { // `c`
								unsafe { cptr++ }
								if *cptr == 116 { // `t`
									return 97 // select
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 104 { // `h`
					unsafe { cptr++ }
					if *cptr == 97 { // `a`
						unsafe { cptr++ }
						if *cptr == 114 { // `r`
							unsafe { cptr++ }
							if *cptr == 101 { // `e`
								unsafe { cptr++ }
								if *cptr == 100 { // `d`
									return 92 // shared
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 105 { // `i`
					unsafe { cptr++ }
					if *cptr == 122 { // `z`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 111 { // `o`
								unsafe { cptr++ }
								if *cptr == 102 { // `f`
									return 98 // sizeof
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 116 { // `t`
					unsafe { cptr++ }
					if *cptr == 97 { // `a`
						unsafe { cptr++ }
						if *cptr == 116 { // `t`
							unsafe { cptr++ }
							if *cptr == 105 { // `i`
								unsafe { cptr++ }
								if *cptr == 99 { // `c`
									return 111 // static
								}
								return -1
							}
							return -1
						}
						return -1
					}
					if *cptr == 114 { // `r`
						unsafe { cptr++ }
						if *cptr == 117 { // `u`
							unsafe { cptr++ }
							if *cptr == 99 { // `c`
								unsafe { cptr++ }
								if *cptr == 116 { // `t`
									return 103 // struct
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 116 { // `t`
				unsafe { cptr++ }
				if *cptr == 121 { // `y`
					unsafe { cptr++ }
					if *cptr == 112 { // `p`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 111 { // `o`
								unsafe { cptr++ }
								if *cptr == 102 { // `f`
									return 106 // typeof
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 117 { // `u`
				unsafe { cptr++ }
				if *cptr == 110 { // `n`
					unsafe { cptr++ }
					if *cptr == 115 { // `s`
						unsafe { cptr++ }
						if *cptr == 97 { // `a`
							unsafe { cptr++ }
							if *cptr == 102 { // `f`
								unsafe { cptr++ }
								if *cptr == 101 { // `e`
									return 113 // unsafe
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
		}
		8 {
			if *cptr == 95 { // `_`
				unsafe { cptr++ }
				if *cptr == 95 { // `_`
					unsafe { cptr++ }
					if *cptr == 103 { // `g`
						unsafe { cptr++ }
						if *cptr == 108 { // `l`
							unsafe { cptr++ }
							if *cptr == 111 { // `o`
								unsafe { cptr++ }
								if *cptr == 98 { // `b`
									unsafe { cptr++ }
									if *cptr == 97 { // `a`
										unsafe { cptr++ }
										if *cptr == 108 { // `l`
											return 80 // __global
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 108 { // `l`
					unsafe { cptr++ }
					if *cptr == 105 { // `i`
						unsafe { cptr++ }
						if *cptr == 107 { // `k`
							unsafe { cptr++ }
							if *cptr == 101 { // `e`
								unsafe { cptr++ }
								if *cptr == 108 { // `l`
									unsafe { cptr++ }
									if *cptr == 121 { // `y`
										unsafe { cptr++ }
										if *cptr == 95 { // `_`
											return 100 // _likely_
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 99 { // `c`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 110 { // `n`
						unsafe { cptr++ }
						if *cptr == 116 { // `t`
							unsafe { cptr++ }
							if *cptr == 105 { // `i`
								unsafe { cptr++ }
								if *cptr == 110 { // `n`
									unsafe { cptr++ }
									if *cptr == 117 { // `u`
										unsafe { cptr++ }
										if *cptr == 101 { // `e`
											return 73 // continue
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
			if *cptr == 118 { // `v`
				unsafe { cptr++ }
				if *cptr == 111 { // `o`
					unsafe { cptr++ }
					if *cptr == 108 { // `l`
						unsafe { cptr++ }
						if *cptr == 97 { // `a`
							unsafe { cptr++ }
							if *cptr == 116 { // `t`
								unsafe { cptr++ }
								if *cptr == 105 { // `i`
									unsafe { cptr++ }
									if *cptr == 108 { // `l`
										unsafe { cptr++ }
										if *cptr == 101 { // `e`
											return 112 // volatile
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
		}
		9 {
			if *cptr == 105 { // `i`
				unsafe { cptr++ }
				if *cptr == 110 { // `n`
					unsafe { cptr++ }
					if *cptr == 116 { // `t`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 114 { // `r`
								unsafe { cptr++ }
								if *cptr == 102 { // `f`
									unsafe { cptr++ }
									if *cptr == 97 { // `a`
										unsafe { cptr++ }
										if *cptr == 99 { // `c`
											unsafe { cptr++ }
											if *cptr == 101 { // `e`
												return 86 // interface
											}
											return -1
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 115 { // `s`
					unsafe { cptr++ }
					if *cptr == 114 { // `r`
						unsafe { cptr++ }
						if *cptr == 101 { // `e`
							unsafe { cptr++ }
							if *cptr == 102 { // `f`
								unsafe { cptr++ }
								if *cptr == 116 { // `t`
									unsafe { cptr++ }
									if *cptr == 121 { // `y`
										unsafe { cptr++ }
										if *cptr == 112 { // `p`
											unsafe { cptr++ }
											if *cptr == 101 { // `e`
												return 99 // isreftype
											}
											return -1
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
		}
		10 {
			if *cptr == 95 { // `_`
				unsafe { cptr++ }
				if *cptr == 95 { // `_`
					unsafe { cptr++ }
					if *cptr == 111 { // `o`
						unsafe { cptr++ }
						if *cptr == 102 { // `f`
							unsafe { cptr++ }
							if *cptr == 102 { // `f`
								unsafe { cptr++ }
								if *cptr == 115 { // `s`
									unsafe { cptr++ }
									if *cptr == 101 { // `e`
										unsafe { cptr++ }
										if *cptr == 116 { // `t`
											unsafe { cptr++ }
											if *cptr == 111 { // `o`
												unsafe { cptr++ }
												if *cptr == 102 { // `f`
													return 102 // __offsetof
												}
												return -1
											}
											return -1
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				if *cptr == 117 { // `u`
					unsafe { cptr++ }
					if *cptr == 110 { // `n`
						unsafe { cptr++ }
						if *cptr == 108 { // `l`
							unsafe { cptr++ }
							if *cptr == 105 { // `i`
								unsafe { cptr++ }
								if *cptr == 107 { // `k`
									unsafe { cptr++ }
									if *cptr == 101 { // `e`
										unsafe { cptr++ }
										if *cptr == 108 { // `l`
											unsafe { cptr++ }
											if *cptr == 121 { // `y`
												unsafe { cptr++ }
												if *cptr == 95 { // `_`
													return 101 // _unlikely_
												}
												return -1
											}
											return -1
										}
										return -1
									}
									return -1
								}
								return -1
							}
							return -1
						}
						return -1
					}
					return -1
				}
				return -1
			}
		}
		else {}
	}
	return -1
}
